// swift-tools-version:5.9
// Syncwright. Copyright © 2026 Ray Munro. All rights reserved.
import PackageDescription

let package = Package(
    name: "Syncwright",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Syncwright", path: "Sources/Syncwright")
    ]
)
