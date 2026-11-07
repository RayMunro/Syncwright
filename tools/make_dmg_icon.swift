// Syncwright
// Copyright © 2026 Ray Munro. All rights reserved.

// Draws the disk image's icon: the app icon rising out of a glossy drive, with an install badge.
// Usage: swift tools/make_dmg_icon.swift <AppIcon-1024.png> <output.png>
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func withShadow(_ blur: CGFloat, _ dy: CGFloat, _ alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.shadowBlurRadius = blur
    s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

// Soft glow behind everything, in the app's teal.
NSGradient(colors: [color(0x1C9C9A, 0.22), color(0x1C9C9A, 0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: 150, y: 110, width: 724, height: 300)), relativeCenterPosition: .zero)

// The drive.
let body = NSRect(x: 132, y: 150, width: 760, height: 270)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 70, yRadius: 70)
withShadow(40, -24, 0.5) {
    color(0x2B2F77).setFill()
    bodyPath.fill()
}
NSGraphicsContext.saveGraphicsState()
bodyPath.addClip()
NSGradient(colors: [color(0x3A2F86), color(0x2D5FA8), color(0x1C9C9A)], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
    .draw(in: body, angle: -20)
// Top bevel and gloss.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.38), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: body.minX, y: body.maxY - 110, width: body.width, height: 110), angle: -90)
let gloss = NSBezierPath()
gloss.move(to: NSPoint(x: body.minX, y: body.maxY - 40))
gloss.curve(to: NSPoint(x: body.maxX, y: body.maxY - 150), controlPoint1: NSPoint(x: 420, y: body.maxY - 10),
            controlPoint2: NSPoint(x: 700, y: body.maxY - 120))
gloss.line(to: NSPoint(x: body.maxX, y: body.maxY))
gloss.line(to: NSPoint(x: body.minX, y: body.maxY))
gloss.close()
NSColor.white.withAlphaComponent(0.10).setFill()
gloss.fill()
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.35).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 68, yRadius: 68)
rim.lineWidth = 4
rim.stroke()

// Front detail: a slot and a glowing status light.
color(0x0E1340, 0.55).setFill()
NSBezierPath(roundedRect: NSRect(x: body.minX + 70, y: body.minY + 62, width: 300, height: 18), xRadius: 9, yRadius: 9).fill()
let led = NSPoint(x: body.minX + 410, y: body.minY + 71)
NSGradient(colors: [color(0x6CFFE6, 0.9), color(0x6CFFE6, 0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: led.x - 34, y: led.y - 34, width: 68, height: 68)), relativeCenterPosition: .zero)
color(0xC9FFF6).setFill()
NSBezierPath(ovalIn: NSRect(x: led.x - 11, y: led.y - 11, width: 22, height: 22)).fill()

// The app icon rising out of the drive.
let appIcon = NSImage(contentsOfFile: CommandLine.arguments[1])!
let iconRect = NSRect(x: 512 - 300, y: 300, width: 600, height: 600)
withShadow(36, -18, 0.55) {
    appIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
}

// Install badge: a bright disc with a down arrow.
let badge = NSRect(x: 688, y: 96, width: 250, height: 250)
withShadow(26, -12, 0.5) {
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badge).fill()
}
let disc = NSBezierPath(ovalIn: badge.insetBy(dx: 16, dy: 16))
NSGraphicsContext.saveGraphicsState()
disc.addClip()
NSGradient(colors: [color(0x2EE6B8), color(0x1C9C9A), color(0x2D5FA8)], atLocations: [0, 0.5, 1], colorSpace: .deviceRGB)!
    .draw(in: badge, angle: -70)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: badge.minX, y: badge.midY, width: badge.width, height: badge.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()
let arrow = NSBezierPath()
arrow.lineWidth = 30
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: badge.midX, y: badge.midY + 70))
arrow.line(to: NSPoint(x: badge.midX, y: badge.midY - 62))
arrow.move(to: NSPoint(x: badge.midX - 58, y: badge.midY - 6))
arrow.line(to: NSPoint(x: badge.midX, y: badge.midY - 66))
arrow.line(to: NSPoint(x: badge.midX + 58, y: badge.midY - 6))
NSColor.white.setStroke()
withShadow(6, -3, 0.25) { arrow.stroke() }

NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("wrote", CommandLine.arguments[2])
