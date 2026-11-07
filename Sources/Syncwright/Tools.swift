// Syncwright
// Copyright © 2026 Ray Munro. All rights reserved.

import Foundation

enum ToolError: LocalizedError {
    case notFound(String)
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let n): return "\(n) was not found. Install it with: brew install ffmpeg"
        case .failed(let m): return m
        }
    }
}

enum Tools {
    static func locate(_ name: String) throws -> String {
        var dirs: [String] = []
        if let res = Bundle.main.resourcePath { dirs.append(res) }
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/local/bin"]
        for d in dirs {
            let p = d + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        throw ToolError.notFound(name)
    }

    /// Runs a tool, returning stdout bytes and stderr text.
    @discardableResult
    static func run(_ name: String, _ args: [String]) throws -> (out: Data, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: try locate(name))
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice

        let errLock = NSLock()
        var errData = Data()
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            errLock.lock(); errData.append(d); errLock.unlock()
        }
        try p.run()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        errPipe.fileHandleForReading.readabilityHandler = nil
        errLock.lock()
        let err = String(decoding: errData, as: UTF8.self)
        errLock.unlock()
        if p.terminationStatus != 0 {
            let tail = err.split(separator: "\n").suffix(6).joined(separator: "\n")
            throw ToolError.failed("\(name) failed:\n\(tail)")
        }
        return (out, err)
    }

    /// Runs a tool and feeds stdout to `chunk` incrementally (constant memory).
    static func stream(_ name: String, _ args: [String], chunk: (Data) -> Void) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: try locate(name))
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        let errLock = NSLock()
        var errData = Data()
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            errLock.lock(); errData.append(d); errLock.unlock()
        }
        try p.run()
        let h = outPipe.fileHandleForReading
        while let d = try h.read(upToCount: 1 << 20), !d.isEmpty { chunk(d) }
        p.waitUntilExit()
        errPipe.fileHandleForReading.readabilityHandler = nil
        if p.terminationStatus != 0 {
            errLock.lock(); let err = String(decoding: errData, as: UTF8.self); errLock.unlock()
            let tail = err.split(separator: "\n").suffix(6).joined(separator: "\n")
            throw ToolError.failed("\(name) failed:\n\(tail)")
        }
    }
}
