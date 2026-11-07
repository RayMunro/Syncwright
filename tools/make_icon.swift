// Syncwright
// Copyright © 2026 Ray Munro. All rights reserved.

// Renders Resources/AppIcon-1024.png: a picture frame and an audio waveform locked together on one sync line.
// Usage: swift tools/make_icon.swift
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Background tile (macOS icon grid: 824pt tile inset 100pt, ~185pt corner radius).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
tileShadow.shadowOffset = NSSize(width: 0, height: -10)
tileShadow.shadowBlurRadius = 24
tileShadow.set()
color(0x14213D).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
NSGradient(colors: [color(0x1B1F4B), color(0x1F4E8C), color(0x13A89E)], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
    .draw(in: tile, angle: -60)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

let centreX = size / 2

// Picture: a screen with a play triangle.
let screen = NSRect(x: 214, y: 524, width: 596, height: 292)
NSGraphicsContext.saveGraphicsState()
let sh = NSShadow()
sh.shadowColor = NSColor.black.withAlphaComponent(0.4)
sh.shadowOffset = NSSize(width: 0, height: -14)
sh.shadowBlurRadius = 30
sh.set()
color(0x0F1226).setFill()
NSBezierPath(roundedRect: screen, xRadius: 44, yRadius: 44).fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [color(0x2A2F5E), color(0x12152E)])!
    .draw(in: NSBezierPath(roundedRect: screen, xRadius: 44, yRadius: 44), angle: -90)
// Film-frame ticks along the top and bottom edges.
color(0xFFFFFF, 0.16).setFill()
for i in 0..<12 {
    let x = screen.minX + 34 + CGFloat(i) * 47
    NSBezierPath(roundedRect: NSRect(x: x, y: screen.maxY - 30, width: 26, height: 12), xRadius: 4, yRadius: 4).fill()
    NSBezierPath(roundedRect: NSRect(x: x, y: screen.minY + 18, width: 26, height: 12), xRadius: 4, yRadius: 4).fill()
}
let play = NSBezierPath()
play.move(to: NSPoint(x: centreX - 44, y: screen.midY - 62))
play.line(to: NSPoint(x: centreX - 44, y: screen.midY + 62))
play.line(to: NSPoint(x: centreX + 70, y: screen.midY))
play.close()
NSGradient(colors: [color(0xFFFFFF), color(0xCFE8F7)])!.draw(in: play, angle: -90)

// Sound: a waveform of rounded bars, symmetric about a line.
let waveMid: CGFloat = 330
let heights: [CGFloat] = [40, 78, 130, 96, 168, 124, 200, 150, 110, 176, 84, 132, 60, 100, 44]
let barW: CGFloat = 26, gap: CGFloat = 14
let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var bx = centreX - total / 2
for (i, h) in heights.enumerated() {
    let r = NSRect(x: bx, y: waveMid - h / 2, width: barW, height: h)
    let t = CGFloat(i) / CGFloat(heights.count - 1)
    NSGradient(colors: [color(0xFFB347), color(0xFF7A45)])!.draw(in: NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2), angle: -90)
    _ = t
    bx += barW + gap
}

// The sync line through picture and sound, with a locked marker.
NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = color(0x7CFFD9, 0.9)
glow.shadowOffset = .zero
glow.shadowBlurRadius = 22
glow.set()
color(0x7CFFD9).setFill()
NSBezierPath(roundedRect: NSRect(x: centreX - 5, y: 186, width: 10, height: 650), xRadius: 5, yRadius: 5).fill()
NSGraphicsContext.restoreGraphicsState()
let dot = NSRect(x: centreX - 22, y: 440 - 22, width: 44, height: 44)
color(0x7CFFD9).setFill()
NSBezierPath(ovalIn: dot).fill()
color(0x14213D).setStroke()
let tick = NSBezierPath()
tick.lineWidth = 8; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
tick.move(to: NSPoint(x: centreX - 10, y: 440)); tick.line(to: NSPoint(x: centreX - 2, y: 431)); tick.line(to: NSPoint(x: centreX + 12, y: 449))
tick.stroke()

NSGraphicsContext.current = nil
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let png = root.appendingPathComponent("Resources/AppIcon-1024.png")
try rep.representation(using: .png, properties: [:])!.write(to: png)
print("wrote", png.path)
