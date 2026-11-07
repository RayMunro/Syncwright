// Syncwright
// Copyright © 2026 Ray Munro. All rights reserved.

// Gives a file a custom Finder icon. Usage: swift tools/set_file_icon.swift <icon.png> <file>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: set_file_icon.swift <icon.png> <file>\n".utf8))
    exit(1)
}
exit(NSWorkspace.shared.setIcon(image, forFile: args[2], options: []) ? 0 : 1)
