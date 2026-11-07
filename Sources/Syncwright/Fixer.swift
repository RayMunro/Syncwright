// Syncwright
// Copyright © 2026 Ray Munro. All rights reserved.

import Foundation

enum Fixer {
    /// Remuxes `input` to `output` with audio shifted, copying every stream (no re-encode).
    /// `delay` is how late the audio currently is (seconds). Positive delay -> audio must move earlier,
    /// which is done by holding the video back. Negative -> audio is held back.
    /// The result is verified; a broken output is deleted and an error thrown.
    static func fix(input: String, output: String, delay: Double) throws {
        let ext = URL(fileURLWithPath: input).pathExtension.lowercased()
        let isMov = ["mp4", "m4v", "mov", "m4a"].contains(ext)
        // Never move the video: players like Plex dislike video that starts late (empty edit lists).
        // Audio that is late is trimmed at its start (-ss); audio that is early is delayed (-itsoffset).
        var args = ["-v", "error", "-y", "-i", input]
        if delay >= 0 {
            args += ["-ss", String(format: "%.3f", delay), "-i", input]
        } else {
            args += ["-itsoffset", String(format: "%.3f", -delay), "-i", input]
        }
        args += ["-map", "0:v", "-map", "1:a", "-map", "0:s?"]
        // Data/timecode tracks (tmcd, timed ID3 etc.) are what most often upsets Plex and other players
        // when copied into MP4/MOV, so they are left out there.
        if !isMov { args += ["-map", "0:d?"] }
        args += ["-map_metadata", "0", "-map_chapters", "0", "-map_metadata:s:v:0", "0:s:v:0"]
        let nAudio = (try? audioStreams(input).count) ?? 0
        for k in 0..<nAudio { args += ["-map_metadata:s:a:\(k)", "1:s:a:\(k)"] }
        args += ["-c", "copy", "-ignore_unknown", "-max_interleave_delta", "0"]
        if ["mp4", "m4v"].contains(ext) { args += ["-brand", "mp42"] }
        // Newer ffmpeg adds a 'btrt' box inside subtitle sample entries that Plex's transcoder can reject.
        if isMov { args += ["-movflags", "+faststart", "-write_btrt", "0"] }
        args.append(output)

        do {
            try Tools.run("ffmpeg", args)
            try verify(input: input, output: output, delay: delay)
        } catch {
            try? FileManager.default.removeItem(atPath: output)
            throw error
        }
    }

    /// Checks the new file has the same streams/codecs and the right length, and that every packet can be read.
    static func verify(input: String, output: String, delay: Double, strictCodecs: Bool = true) throws {
        func streams(_ p: String) throws -> [String] {
            let r = try Tools.run("ffprobe", ["-v", "error", "-show_entries",
                                              "stream=codec_type,codec_name:stream_disposition=attached_pic",
                                              "-of", "json", p])
            guard let o = try JSONSerialization.jsonObject(with: r.out) as? [String: Any],
                  let ss = o["streams"] as? [[String: Any]] else { return [] }
            return ss.compactMap { s in
                let t = s["codec_type"] as? String ?? "", c = s["codec_name"] as? String ?? ""
                return (t == "data") ? nil : (strictCodecs ? "\(t):\(c)" : t)
            }.sorted()
        }
        let a = try streams(input), b = try streams(output)
        // data streams are allowed to be dropped; everything else must match exactly
        if a != b {
            throw ToolError.failed("Verification failed: streams differ.\nOriginal: \(a.joined(separator: ", "))\nNew file: \(b.joined(separator: ", "))")
        }
        let din = try Analyzer.probe(input).duration, dout = try Analyzer.probe(output).duration
        if dout < din - 2 || dout > din + abs(delay) + 2 {
            throw ToolError.failed(String(format: "Verification failed: new file is %.1f s, original %.1f s.", dout, din))
        }
        // Read every packet of every stream to catch a truncated or damaged file.
        try Tools.run("ffmpeg", ["-v", "error", "-i", output, "-map", "0", "-c", "copy", "-f", "null", "-"])
    }

    // MARK: Re-encode audio (video and subtitles are still copied untouched)

    struct AudioParams { var codec: String; var bitrate: Int; var rate: Int; var channels: Int; var lang: String? }

    static func audioStreams(_ path: String) throws -> [AudioParams] {
        let r = try Tools.run("ffprobe", ["-v", "error", "-select_streams", "a", "-show_entries",
                                          "stream=codec_name,bit_rate,sample_rate,channels", "-of", "json", path])
        guard let o = try JSONSerialization.jsonObject(with: r.out) as? [String: Any],
              let ss = o["streams"] as? [[String: Any]] else { return [] }
        return ss.map { s in
            AudioParams(codec: s["codec_name"] as? String ?? "aac",
                        bitrate: Int(s["bit_rate"] as? String ?? "") ?? 0,
                        rate: Int(s["sample_rate"] as? String ?? "") ?? 48000,
                        channels: s["channels"] as? Int ?? 2, lang: nil)
        }
    }

    /// Encoder for the same codec as the source where possible.
    static func encoder(for codec: String) -> (name: String, same: Bool) {
        switch codec {
        case "aac": return ("aac", true)
        case "ac3": return ("ac3", true)
        case "eac3": return ("eac3", true)
        case "mp3": return ("libmp3lame", true)
        case "opus": return ("libopus", true)
        case "vorbis": return ("libvorbis", true)
        case "flac": return ("flac", true)
        case "alac": return ("alac", true)
        case "pcm_s16le", "pcm_s24le", "pcm_s16be": return (codec, true)
        default: return ("aac", false)
        }
    }

    /// Delay curve (audio lateness minus container offset) as (video time, lag) knots.
    static func knots(_ r: SyncResult, manualDelay: Double, duration: Double) -> [(Double, Double)] {
        let c = r.containerDelay
        let shift = manualDelay - r.totalDelay
        let good = r.windows.filter { $0.valid }.map { ($0.time, $0.delay - c) }
        var pts: [(Double, Double)]
        if r.pattern == .varying && good.count >= 3 {
            // 3-point median to ignore the odd bad window
            var sm = good
            for i in 1..<(good.count - 1) {
                sm[i].1 = [good[i - 1].1, good[i].1, good[i + 1].1].sorted()[1]
            }
            pts = [(0, sm.first!.1)] + sm + [(duration, sm.last!.1)]
        } else if r.pattern == .drifting && good.count >= 3 {
            let n = Double(good.count)
            let mx = good.reduce(0) { $0 + $1.0 } / n, my = good.reduce(0) { $0 + $1.1 } / n
            let b = Analyzer.linearSlope(good), a = my - b * mx
            pts = [(0, a), (duration, a + b * duration)]
        } else {
            let l = (r.contentDelay ?? 0)
            pts = [(0, l), (duration, l)]
        }
        // strictly increasing times
        var out: [(Double, Double)] = []
        for p in pts where p.0 >= 0 && p.0 <= duration && (out.last == nil || p.0 - out.last!.0 > 1) { out.append((p.0, p.1 + shift)) }
        if out.count < 2 { out = [(0, (r.contentDelay ?? 0) + shift), (duration, (r.contentDelay ?? 0) + shift)] }
        return out
    }

    static func fixReencode(input: String, output: String, result r: SyncResult, manualDelay: Double) throws {
        let info = try Analyzer.probe(input)
        let ks = knots(r, manualDelay: manualDelay, duration: info.duration)
        let audios = try audioStreams(input)
        guard !audios.isEmpty else { throw ToolError.failed("No audio stream found.") }
        let ext = URL(fileURLWithPath: input).pathExtension.lowercased()
        let isMov = ["mp4", "m4v", "mov"].contains(ext)

        var graph: [String] = []
        for k in audios.indices {
            let nSeg = ks.count - 1
            var labels: [String] = []
            if nSeg > 1 {
                graph.append("[1:a:\(k)]asetpts=PTS-STARTPTS,asplit=\(nSeg)" + (0..<nSeg).map { "[s\(k)_\($0)]" }.joined())
            }
            for i in 0..<nSeg {
                let (t0, l0) = ks[i], (t1, l1) = ks[i + 1]
                var x = t0 + l0
                let y = t1 + l1
                var out = t1 - t0
                var pad = 0.0
                if x < 0 { pad = -x; x = 0; out -= pad }
                let tempo = min(2.0, max(0.5, (y - x) / max(out, 0.1)))
                var f = String(format: "atrim=start=%.4f:end=%.4f,asetpts=PTS-STARTPTS,atempo=%.7f", x, y, tempo)
                if pad > 0 { f += String(format: ",adelay=%d:all=1", Int(pad * 1000)) }
                let src = nSeg > 1 ? "[s\(k)_\(i)]" : "[1:a:\(k)]asetpts=PTS-STARTPTS,"
                graph.append(src + (nSeg > 1 ? "" : "") + f + "[c\(k)_\(i)]")
                labels.append("[c\(k)_\(i)]")
            }
            graph.append(labels.joined() + "concat=n=\(nSeg):v=0:a=1[a\(k)]")
        }

        var args = ["-v", "error", "-y",
                    "-i", input,
                    "-itsoffset", String(format: "%.3f", info.videoStart), "-i", input,
                    "-filter_complex", graph.joined(separator: ";"),
                    "-map", "0:v"]
        for k in audios.indices { args += ["-map", "[a\(k)]"] }
        args += ["-map", "0:s?"]
        if !isMov { args += ["-map", "0:d?"] }
        args += ["-map_metadata", "0", "-map_chapters", "0", "-c:v", "copy", "-c:s", "copy", "-ignore_unknown"]
        for (k, a) in audios.enumerated() {
            let enc = encoder(for: a.codec).name
            args += ["-c:a:\(k)", enc, "-ar:a:\(k)", "\(a.rate)", "-ac:a:\(k)", "\(a.channels)",
                     "-map_metadata:s:a:\(k)", "0:s:a:\(k)"]
            if !["flac", "alac"].contains(enc) && !enc.hasPrefix("pcm") {
                let br = a.bitrate > 0 ? a.bitrate : 64000 * a.channels
                args += ["-b:a:\(k)", "\(br)"]
            }
        }
        if isMov { args += ["-movflags", "+faststart", "-write_btrt", "0"] }
        args.append(output)

        do {
            try Tools.run("ffmpeg", args)
            try verify(input: input, output: output, delay: 0, strictCodecs: false)
        } catch {
            try? FileManager.default.removeItem(atPath: output)
            throw error
        }
    }

    static func defaultOutput(for input: String) -> String {
        let u = URL(fileURLWithPath: input)
        let name = u.deletingPathExtension().lastPathComponent + "_synced." + u.pathExtension
        return u.deletingLastPathComponent().appendingPathComponent(name).path
    }
}
