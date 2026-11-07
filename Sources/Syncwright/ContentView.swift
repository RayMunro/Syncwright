// Syncwright
// Copyright © 2026 Ray Munro. All rights reserved.

import SwiftUI
import Charts
import UniformTypeIdentifiers

@MainActor
final class FileItem: ObservableObject, Identifiable {
    enum State { case queued, analyzing, analyzed, fixing, fixed, failed }
    let id = UUID()
    let path: String
    @Published var state: State = .queued
    @Published var progress = 0.0
    @Published var label = "Waiting"
    @Published var result: SyncResult?
    @Published var offsetMs = 0.0
    @Published var output: String?
    @Published var error: String?

    init(path: String) { self.path = path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var needsFix: Bool { result != nil && abs(offsetMs) >= 40 && (result!.confidence == .high || result!.confidence == .medium) }
}

@MainActor
final class Model: ObservableObject {
    @Published var items: [FileItem] = []
    @Published var selection: UUID?
    private var working = false

    var selected: FileItem? { items.first { $0.id == selection } }

    func add(_ paths: [String]) {
        for p in paths where !items.contains(where: { $0.path == p }) {
            items.append(FileItem(path: p))
        }
        if selection == nil { selection = items.first?.id }
        pump()
    }

    func recheck(_ item: FileItem) {
        item.state = .queued; item.result = nil; item.output = nil; item.error = nil
        pump()
    }

    func pump() {
        guard !working, let next = items.first(where: { $0.state == .queued }) else { return }
        working = true
        next.state = .analyzing; next.progress = 0; next.label = "Starting"
        let path = next.path
        Task.detached {
            do {
                let r = try Analyzer.analyze(path) { f, l in
                    Task { @MainActor in next.progress = f; next.label = l }
                }
                await MainActor.run {
                    next.result = r
                    next.offsetMs = (r.totalDelay * 1000).rounded()
                    next.state = .analyzed
                    self.working = false; self.pump()
                }
            } catch {
                await MainActor.run {
                    next.error = error.localizedDescription; next.state = .failed
                    self.working = false; self.pump()
                }
            }
        }
    }

    func fix(_ item: FileItem) {
        guard item.state == .analyzed || item.state == .fixed || item.state == .failed else { return }
        let out = uniqueOutput(for: item.path)
        let delay = item.offsetMs / 1000, path = item.path
        item.state = .fixing; item.error = nil
        Task.detached {
            do {
                try Fixer.fix(input: path, output: out, delay: delay)
                await MainActor.run { item.output = out; item.state = .fixed }
            } catch {
                await MainActor.run { item.error = error.localizedDescription; item.state = .failed }
            }
        }
    }

    func fixReencode(_ item: FileItem) {
        guard let r = item.result else { return }
        let out = uniqueOutput(for: item.path)
        let delay = item.offsetMs / 1000, path = item.path
        item.state = .fixing; item.error = nil
        Task.detached {
            do {
                try Fixer.fixReencode(input: path, output: out, result: r, manualDelay: delay)
                await MainActor.run { item.output = out; item.state = .fixed }
            } catch {
                await MainActor.run { item.error = error.localizedDescription; item.state = .failed }
            }
        }
    }

    func fixAll() { for i in items where i.state == .analyzed && i.needsFix { fix(i) } }

    func uniqueOutput(for input: String) -> String {
        var out = Fixer.defaultOutput(for: input)
        var n = 2
        while FileManager.default.fileExists(atPath: out) {
            let u = URL(fileURLWithPath: Fixer.defaultOutput(for: input))
            out = u.deletingLastPathComponent()
                .appendingPathComponent(u.deletingPathExtension().lastPathComponent + "_\(n)." + u.pathExtension).path
            n += 1
        }
        return out
    }
}

struct ContentView: View {
    @StateObject private var model = Model()
    @State private var targeted = false

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 230, idealWidth: 270, maxWidth: 400)
            detail.frame(minWidth: 380)
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { model.add(expand(url)) } }
                }
            }
            return true
        }
        .overlay(targeted ? RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3).padding(4) : nil)
    }

    // MARK: Sidebar

    var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                ForEach(model.items) { item in FileRow(item: item).tag(item.id) }
            }
            .overlay {
                if model.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 30))
                        Text("Drop episodes or a folder here").foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Button("Add...") { choose() }
                Spacer()
                Button("Fix All Needed") { model.fixAll() }
                    .disabled(!model.items.contains { $0.state == .analyzed && $0.needsFix })
            }.padding(10)
        }
    }

    // MARK: Detail

    @ViewBuilder var detail: some View {
        if let item = model.selected { DetailView(item: item, model: model) }
        else { Text("Select a file").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audiovisualContent]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { model.add(panel.urls.flatMap(expand)) }
    }

    /// Expands folders to the video files inside them.
    func expand(_ url: URL) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue { return [url.path] }
        let exts: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "ts", "m2ts", "mpg", "mpeg", "webm", "wmv"]
        let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles])
        var found: [String] = []
        while let f = en?.nextObject() as? URL {
            let stem = f.deletingPathExtension().lastPathComponent
            if exts.contains(f.pathExtension.lowercased()) && !stem.hasSuffix("_synced") { found.append(f.path) }
        }
        return found.sorted()
    }
}

struct FileRow: View {
    @ObservedObject var item: FileItem
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name).lineLimit(1).truncationMode(.middle)
            switch item.state {
            case .queued: Text("Waiting").font(.caption).foregroundStyle(.secondary)
            case .analyzing:
                ProgressView(value: item.progress).controlSize(.small)
                Text(item.label).font(.caption).foregroundStyle(.secondary)
            case .analyzed:
                if let r = item.result {
                    Text(summary(r)).font(.caption).foregroundStyle(color(r))
                }
            case .fixing: Text("Fixing...").font(.caption).foregroundStyle(.secondary)
            case .fixed: Label("Fixed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            case .failed: Label("Failed", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
            }
        }.padding(.vertical, 2)
    }
    func summary(_ r: SyncResult) -> String {
        if r.confidence == .none { return "Could not determine" }
        let ms = Int((r.totalDelay * 1000).rounded())
        if abs(ms) < 40 { return "In sync" }
        return ms > 0 ? "Audio \(ms) ms late" : "Audio \(-ms) ms early"
    }
    func color(_ r: SyncResult) -> Color {
        if r.confidence == .none { return .orange }
        return abs(r.totalDelay) < 0.04 ? .green : .primary
    }
}

struct DetailView: View {
    @ObservedObject var item: FileItem
    let model: Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.name).font(.title3.bold()).lineLimit(2)
                switch item.state {
                case .queued: Text("Waiting to be checked").foregroundStyle(.secondary)
                case .analyzing:
                    ProgressView(value: item.progress)
                    Text("\(item.label) (\(Int(item.progress * 100))%)").foregroundStyle(.secondary)
                default: EmptyView()
                }
                if let r = item.result { resultView(r) }
                if let e = item.error { Text(e).foregroundStyle(.red).textSelection(.enabled) }
                if let o = item.output {
                    VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Saved \(URL(fileURLWithPath: o).lastPathComponent)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: o)])
                        }
                        Button("Check Result") { model.add([o]) }
                    }
                    }
                }
            }.padding(20)
        }
    }

    @ViewBuilder func resultView(_ r: SyncResult) -> some View {
        HStack {
            Text(verdict(r)).font(.title2.bold())
            Spacer()
            Text("Confidence: \(r.confidence.rawValue)").foregroundStyle(.secondary)
        }
        Text(String(format: "Checked %@ in %d sections, %d matched. Container offset %+.0f ms.",
                    duration(r.duration), r.windows.count, r.validWindows, r.containerDelay * 1000))
            .font(.callout).foregroundStyle(.secondary)

        if !r.windows.isEmpty { chart(r) }
        if !r.note.isEmpty { Text(r.note).font(.callout).foregroundStyle(.orange) }

        Divider()
        HStack {
            Text("Audio delay to remove (ms):")
            TextField("", value: $item.offsetMs, format: .number.precision(.fractionLength(0)))
                .frame(width: 80).textFieldStyle(.roundedBorder)
            Stepper("", value: $item.offsetMs, step: 10).labelsHidden()
        }
        Text("Positive means the sound arrives after the picture. Fixing copies every stream unchanged (same container, same codecs, no re-encoding) and saves a new file next to the original with _synced in its name.")
            .font(.caption).foregroundStyle(.secondary)
        if r.confidence != .none && (r.pattern != .constant || item.error != nil) {
            VStack(alignment: .leading, spacing: 6) {
                Text(r.pattern == .constant
                     ? "The lossless fix did not work for this file."
                     : "A single shift can't keep this file in sync all the way through.")
                    .font(.callout.bold())
                Text("Re-encoding is needed. Syncwright can re-encode only the audio, using the same codec, bitrate and channels, and bend its timing to follow the picture. The video, subtitles and chapters are copied untouched. The container stays the same.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Fix by Re-encoding Audio") { model.fixReencode(item) }
                    .disabled(item.state == .fixing)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        }
        HStack {
            Button("Re-check") { model.recheck(item) }
            Spacer()
            Button("Fix Sync") { model.fix(item) }
                .buttonStyle(.borderedProminent)
                .disabled(item.state == .fixing || abs(item.offsetMs) < 1)
        }
    }

    func chart(_ r: SyncResult) -> some View {
        Chart {
            RuleMark(y: .value("Target", 0)).foregroundStyle(.green.opacity(0.5))
            ForEach(r.windows) { p in
                PointMark(x: .value("Minutes", p.time / 60), y: .value("Delay ms", p.delay * 1000))
                    .foregroundStyle(p.valid ? Color.accentColor : Color.gray.opacity(0.4))
            }
        }
        .chartXAxisLabel("Minutes into file")
        .chartYAxisLabel("Audio delay (ms)")
        .frame(height: 170)
    }

    func verdict(_ r: SyncResult) -> String {
        if r.confidence == .none { return "Could not determine sync" }
        let ms = Int((r.totalDelay * 1000).rounded())
        if abs(ms) < 40 { return "In sync (\(ms) ms)" }
        return ms > 0 ? "Audio is \(ms) ms late" : "Audio is \(-ms) ms early"
    }

    func duration(_ s: Double) -> String {
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }
}
