// Syncwright
// Copyright © 2026 Ray Munro. All rights reserved.

import SwiftUI

@main
struct SyncwrightApp: App {
    init() {
        // Headless mode for testing: Syncwright --analyze file [--fix out delayMs]
        let a = CommandLine.arguments
        if a.count >= 3, a[1] == "--analyze" {
            do {
                let r = try Analyzer.analyze(a[2]) { _, _ in }
                print(String(format: "total=%.0fms container=%.0fms content=%@ conf=%@ pattern=%@ valid=%d/%d spread=%.0fms drift=%.0fms/h dur=%.0fs",
                             r.totalDelay * 1000, r.containerDelay * 1000,
                             r.contentDelay.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a",
                             r.confidence.rawValue, "\(r.pattern)", r.validWindows, r.windows.count,
                             r.spread * 1000, r.driftPerHour * 1000, r.duration))
                if a.count >= 5, a[3] == "--reencode" {
                    try Fixer.fixReencode(input: a[2], output: a[4], result: r, manualDelay: r.totalDelay)
                    print("re-encoded audio -> \(a[4])")
                }
                if a.count >= 6, a[3] == "--fix" {
                    try Fixer.fix(input: a[2], output: a[4], delay: (Double(a[5]) ?? 0) / 1000)
                    print("fixed -> \(a[4])")
                }
            } catch { print("ERROR: \(error.localizedDescription)") }
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
    }
}
