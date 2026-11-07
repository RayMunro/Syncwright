// Syncwright
// Copyright © 2026 Ray Munro. All rights reserved.

import Foundation
import Vision
import CoreVideo

struct WindowPoint: Identifiable {
    var id: Int
    var time: Double        // window centre, seconds
    var delay: Double       // total audio delay in this window, seconds
    var valid: Bool
}

struct SyncResult {
    enum Confidence: String { case high = "High", medium = "Medium", low = "Low", none = "None" }
    enum Pattern { case constant, drifting, varying, unknown }

    /// Seconds the audio plays AFTER the picture (positive = audio late, negative = early).
    var totalDelay: Double
    var containerDelay: Double
    var contentDelay: Double?
    var confidence: Confidence
    var pattern: Pattern
    var windows: [WindowPoint]
    var validWindows: Int
    var spread: Double              // 10th-90th percentile range of window delays, seconds
    var driftPerHour: Double        // seconds per hour (linear fit)
    var duration: Double
    var note: String
}

struct StreamInfo {
    var videoStart: Double
    var audioStart: Double
    var hasVideo: Bool
    var hasAudio: Bool
    var duration: Double
}

enum Analyzer {
    static let rate = 25.0              // series rate (Hz); peaks are refined to sub-frame precision
    static let globalLag = 3.0          // seconds searched for the overall offset
    static let windowSeconds = 240      // per-window analysis length
    static let windowLag = 1.0          // search +/- this around the overall offset per window
    static let fw = 640, fh = 360

    // MARK: Probe

    static func probe(_ path: String) throws -> StreamInfo {
        let r = try Tools.run("ffprobe", ["-v", "error", "-show_entries",
                                          "stream=codec_type,start_time:format=duration", "-of", "json", path])
        guard let obj = try JSONSerialization.jsonObject(with: r.out) as? [String: Any],
              let streams = obj["streams"] as? [[String: Any]] else {
            throw ToolError.failed("Could not read stream information.")
        }
        var v: Double?, a: Double?
        for s in streams {
            let t = s["codec_type"] as? String
            let st = Double(s["start_time"] as? String ?? "") ?? 0
            if t == "video", v == nil { v = st }
            if t == "audio", a == nil { a = st }
        }
        let dur = Double((obj["format"] as? [String: Any])?["duration"] as? String ?? "") ?? 0
        return StreamInfo(videoStart: v ?? 0, audioStart: a ?? 0, hasVideo: v != nil, hasAudio: a != nil, duration: dur)
    }

    // MARK: Main entry

    struct Series { var audioEnv: [Double]; var audioFlux: [Double]; var mouth: [Double]; var mouthMask: [Bool]; var motion: [Double] }

    /// progress: fraction 0...1 and a short label.
    static func analyze(_ path: String, progress: @escaping (Double, String) -> Void) throws -> SyncResult {
        progress(0, "Reading stream info")
        let info = try probe(path)
        guard info.hasVideo, info.hasAudio else {
            throw ToolError.failed("The file needs both a video and an audio stream.")
        }
        let container = info.audioStart - info.videoStart
        let debug = ProcessInfo.processInfo.environment["SYNCWRIGHT_DEBUG"] != nil

        var aEnv: [Double] = [], aFlux: [Double] = []
        var vm: [Double] = [], vmask: [Bool] = [], vmotion: [Double] = []
        var aErr: Error?, vErr: Error?
        let lock = NSLock()
        var vFrac = 0.0, aFrac = 0.0
        func report() { lock.lock(); let f = 0.02 + 0.93 * (0.1 * aFrac + 0.9 * vFrac); lock.unlock(); progress(f, "Scanning whole file") }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            do { (aEnv, aFlux) = try audioSeries(path, duration: info.duration) { f in lock.lock(); aFrac = f; lock.unlock(); report() } }
            catch { aErr = error }
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            do { (vm, vmask, vmotion) = try videoSeries(path, duration: info.duration) { f in lock.lock(); vFrac = f; lock.unlock(); report() } }
            catch { vErr = error }
            group.leave()
        }
        group.wait()
        if let e = aErr ?? vErr { throw e }

        progress(0.96, "Correlating")
        let n = min(aEnv.count, vm.count, vmotion.count, aFlux.count)
        let dur = Double(n) / rate
        func empty(_ note: String) -> SyncResult {
            SyncResult(totalDelay: container, containerDelay: container, contentDelay: nil, confidence: .none,
                       pattern: .unknown, windows: [], validWindows: 0, spread: 0, driftPerHour: 0, duration: dur, note: note)
        }
        guard n > Int(rate * 30) else { return empty("Clip too short for content analysis. Using container timestamps only.") }

        let allTrue = [Bool](repeating: true, count: n)
        let faceFrames = vmask[0..<n].filter { $0 }.count
        // Two methods: lip movement vs speech loudness, and picture motion vs sound onsets.
        let methods: [(name: String, a: [Double], v: [Double], m: [Bool])] = [
            ("lip movement and speech", Array(aEnv[0..<n]), Array(vm[0..<n]), Array(vmask[0..<n])),
            ("picture motion and sound", Array(aFlux[0..<n]), Array(vmotion[0..<n]), allTrue),
        ]
        var best: (idx: Int, centre: Int, z: Double, peak: Double)?
        for (i, m) in methods.enumerated() {
            if i == 0 && faceFrames < Int(rate * 20) { continue }       // too few faces to be meaningful
            let (a, v) = (standardize(m.a, m.m), standardize(m.v, m.m))
            let G = Int(globalLag * rate)
            let c = xcorr(a, v, m.m, from: 0, to: n, lags: -G...G)
            let (b, z, pk) = peakStats(c)
            if debug { print(String(format: "method %d (%@): lag=%.0fms peak=%.3f z=%.1f faceFrames=%d/%d", i, m.name, Double(b - G) / rate * 1000, pk, z, faceFrames, n)) }
            if best == nil || z > best!.z { best = (i, b - G, z, pk) }
        }
        guard let pick = best, pick.z >= 3.0 else {
            var r = empty("No reliable relationship between sound and picture was found, so the offset could not be determined. Set it by ear if you know it.")
            r.windows = []
            return r
        }
        let m = methods[pick.idx]
        let a = standardize(m.a, m.m), v = standardize(m.v, m.m)

        // Per-window offsets around the overall offset.
        let win = windowSeconds * Int(rate)
        let R = Int(windowLag * rate)
        var points: [WindowPoint] = []
        var start = 0, idx = 0
        while start + win / 2 <= n {
            let end = min(n, start + win)
            let c = xcorr(a, v, m.m, from: start, to: end, lags: (pick.centre - R)...(pick.centre + R))
            let (b, z, pk) = peakStats(c)
            let lag = (Double(pick.centre - R + b) + parabolic(c, b)) / rate
            let ok = z >= 3.0
            if debug { print(String(format: "win %d t=%.0f lag=%.0fms peak=%.3f z=%.1f", idx, Double(start) / rate, lag * 1000, pk, z)) }
            points.append(WindowPoint(id: idx, time: Double(start + end) / 2 / rate, delay: container + lag, valid: ok))
            start += win; idx += 1
        }
        let good = points.filter { $0.valid }

        // Overall (whole-file) lag with sub-frame refinement.
        let G = Int(globalLag * rate)
        let gc = xcorr(a, v, m.m, from: 0, to: n, lags: -G...G)
        let gb = peakStats(gc).idx
        let overall = (Double(gb - G) + parabolic(gc, gb)) / rate

        var note = "Matched \(m.name)."
        var pattern = SyncResult.Pattern.constant
        var spread = 0.0, slope = 0.0
        var content = overall
        if good.count >= 3 {
            let sorted = good.map { $0.delay }.sorted()
            content = sorted[sorted.count / 2] - container
            spread = sorted[Int(Double(sorted.count - 1) * 0.9)] - sorted[Int(Double(sorted.count - 1) * 0.1)]
            slope = linearSlope(good.map { ($0.time, $0.delay) }) * 3600
            let driftTotal = abs(slope) * dur / 3600
            if driftTotal > 0.12 && spread > 0.12 {
                pattern = .drifting
                note += String(format: " Sync drifts by about %.0f ms over the file (%.0f ms/hour). A single shift cannot fix drift without re-encoding audio; the median offset will be applied.", driftTotal * 1000, slope * 1000)
            } else if spread > 0.12 {
                pattern = .varying
                note += String(format: " Offset varies between sections by about %.0f ms (cuts, ad breaks or edits). The median offset will be applied.", spread * 1000)
            }
        }
        let frac = points.isEmpty ? 0 : Double(good.count) / Double(points.count)
        let conf: SyncResult.Confidence = (pick.z >= 6 && frac >= 0.5) ? .high : (pick.z >= 4.5 ? .medium : .low)
        if conf == .low { note += " Weak match: check by ear before applying." }
        return SyncResult(totalDelay: container + content, containerDelay: container, contentDelay: content,
                          confidence: conf, pattern: pattern, windows: points, validWindows: good.count,
                          spread: spread, driftPerHour: slope, duration: dur, note: note)
    }

    // MARK: Series extraction (streaming)

    /// 25 Hz series: (log loudness, loudness onsets).
    static func audioSeries(_ path: String, duration: Double, progress: @escaping (Double) -> Void) throws -> ([Double], [Double]) {
        let sr = 8000
        let step = Int(Double(sr) / rate)
        let frameBytes = step * 2
        var env: [Double] = []
        var carry = Data()
        var total = 0
        let expected = max(duration * Double(sr) * 2, 1)
        try Tools.stream("ffmpeg", ["-v", "error", "-i", path, "-vn", "-map", "0:a:0",
                                    "-af", "highpass=f=150", "-ac", "1", "-ar", "\(sr)", "-f", "s16le", "-"]) { d in
            carry.append(d); total += d.count
            let frames = carry.count / frameBytes
            if frames > 0 {
                carry.withUnsafeBytes { raw in
                    let s = raw.bindMemory(to: Int16.self)
                    for f in 0..<frames {
                        var sum = 0.0
                        for j in 0..<step { let x = Double(s[f * step + j]) / 32768; sum += x * x }
                        env.append(log((sum / Double(step)).squareRoot() + 1e-3))
                    }
                }
                carry = Data(carry.suffix(from: carry.startIndex + frames * frameBytes))
            }
            progress(min(1, Double(total) / expected))
        }
        var flux = [Double](repeating: 0, count: env.count)
        if env.count > 1 { for i in 1..<env.count { flux[i] = max(0, env[i] - env[i - 1]) } }
        return (env, smooth(flux))
    }

    /// 25 Hz series: (mouth openness, face-present mask, motion onsets).
    static func videoSeries(_ path: String, duration: Double, progress: @escaping (Double) -> Void) throws -> ([Double], [Bool], [Double]) {
        let fsz = fw * fh
        var mouth: [Double] = [], mask: [Bool] = [], motion: [Double] = []
        var prev: [UInt8]?
        var carry = Data()
        var total = 0
        let expected = max(duration * rate * Double(fsz), 1)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, fw, fh, kCVPixelFormatType_OneComponent8, nil, &pb)
        guard let buf = pb else { throw ToolError.failed("Could not allocate image buffer.") }
        let vf = "setpts=PTS-STARTPTS,fps=\(Int(rate)),scale=\(fw):\(fh):force_original_aspect_ratio=decrease,pad=\(fw):\(fh):(ow-iw)/2:(oh-ih)/2,format=gray"
        try Tools.stream("ffmpeg", ["-v", "error", "-threads", "0", "-i", path, "-an", "-map", "0:v:0",
                                    "-vf", vf, "-f", "rawvideo", "-"]) { d in
            carry.append(d); total += d.count
            let frames = carry.count / fsz
            if frames > 0 {
                carry.withUnsafeBytes { raw in
                    let b = raw.bindMemory(to: UInt8.self)
                    for f in 0..<frames {
                        let base = f * fsz
                        // motion on a coarse grid
                        var sub = [UInt8](); sub.reserveCapacity((fw / 8) * (fh / 8))
                        var y = 0
                        while y < fh { var x = 0; while x < fw { sub.append(b[base + y * fw + x]); x += 8 }; y += 8 }
                        if let p = prev {
                            var sum = 0
                            for i in 0..<sub.count { sum += abs(Int(sub[i]) - Int(p[i])) }
                            motion.append(Double(sum) / Double(sub.count))
                        } else { motion.append(0) }
                        prev = sub
                        // lip openness via Vision face landmarks
                        CVPixelBufferLockBaseAddress(buf, [])
                        let dst = CVPixelBufferGetBaseAddress(buf)!, bpr = CVPixelBufferGetBytesPerRow(buf)
                        for row in 0..<fh { memcpy(dst + row * bpr, raw.baseAddress! + base + row * fw, fw) }
                        CVPixelBufferUnlockBaseAddress(buf, [])
                        let req = VNDetectFaceLandmarksRequest()
                        try? VNImageRequestHandler(cvPixelBuffer: buf, options: [:]).perform([req])
                        if let face = (req.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }),
                           face.boundingBox.width > 0.03, let pts = face.landmarks?.innerLips?.normalizedPoints, pts.count > 4 {
                            let ys = pts.map { Double($0.y) }, xs = pts.map { Double($0.x) }
                            mouth.append((ys.max()! - ys.min()!) / max(xs.max()! - xs.min()!, 1e-6))
                            mask.append(true)
                        } else { mouth.append(0); mask.append(false) }
                    }
                }
                carry = Data(carry.suffix(from: carry.startIndex + frames * fsz))
            }
            progress(min(1, Double(total) / expected))
        }
        let sm = smooth(motion)
        var onset = [Double](repeating: 0, count: sm.count)
        if sm.count > 1 { for i in 1..<sm.count { onset[i] = max(0, sm[i] - sm[i - 1]) } }
        return (mouth, mask, smooth(onset))
    }

    // MARK: Maths

    /// corr[k - lags.lowerBound] = mean over frames i (with mask[i]) of a[i+k] * v[i]
    static func xcorr(_ a: [Double], _ v: [Double], _ mask: [Bool], from: Int, to: Int, lags: ClosedRange<Int>) -> [Double] {
        var out = [Double](repeating: 0, count: lags.count)
        a.withUnsafeBufferPointer { ap in
            v.withUnsafeBufferPointer { vp in
                mask.withUnsafeBufferPointer { mp in
                    for (j, k) in lags.enumerated() {
                        let lo = max(from, -k), hi = min(to, a.count - k)
                        var s = 0.0, c = 0
                        if hi > lo { for i in lo..<hi where mp[i] { s += ap[i + k] * vp[i]; c += 1 } }
                        out[j] = c > 25 ? s / Double(c) : 0
                    }
                }
            }
        }
        return out
    }

    /// Peak index, significance (z-score of the peak against the rest of the curve), peak value.
    static func peakStats(_ c: [Double]) -> (idx: Int, z: Double, peak: Double) {
        guard let b = c.indices.max(by: { c[$0] < c[$1] }) else { return (0, 0, 0) }
        let excl = Int(0.4 * rate)
        let rest = c.indices.filter { abs($0 - b) > excl }.map { c[$0] }
        guard rest.count > 5 else { return (b, 0, c[b]) }
        let mu = rest.reduce(0, +) / Double(rest.count)
        let sd = max((rest.reduce(0) { $0 + ($1 - mu) * ($1 - mu) } / Double(rest.count)).squareRoot(), 1e-9)
        return (b, (c[b] - mu) / sd, c[b])
    }

    static func parabolic(_ c: [Double], _ b: Int) -> Double {
        guard b > 0, b < c.count - 1 else { return 0 }
        let d = c[b - 1] - 2 * c[b] + c[b + 1]
        return abs(d) > 1e-12 ? 0.5 * (c[b - 1] - c[b + 1]) / d : 0
    }

    static func linearSlope(_ pts: [(Double, Double)]) -> Double {
        let n = Double(pts.count)
        guard n > 2 else { return 0 }
        let mx = pts.reduce(0) { $0 + $1.0 } / n, my = pts.reduce(0) { $0 + $1.1 } / n
        var num = 0.0, den = 0.0
        for (x, y) in pts { num += (x - mx) * (y - my); den += (x - mx) * (x - mx) }
        return den > 0 ? num / den : 0
    }

    static func smooth(_ x: [Double]) -> [Double] {
        guard x.count > 2 else { return x }
        var y = x
        for i in 1..<(x.count - 1) { y[i] = (x[i - 1] + 2 * x[i] + x[i + 1]) / 4 }
        return y
    }

    static func standardize(_ x: [Double], _ mask: [Bool]) -> [Double] {
        var sum = 0.0, cnt = 0
        for i in x.indices where mask[i] { sum += x[i]; cnt += 1 }
        guard cnt > 1 else { return x }
        let m = sum / Double(cnt)
        var vs = 0.0
        for i in x.indices where mask[i] { vs += (x[i] - m) * (x[i] - m) }
        let sd = max((vs / Double(cnt)).squareRoot(), 1e-9)
        return x.indices.map { mask[$0] ? (x[$0] - m) / sd : 0 }
    }
}
