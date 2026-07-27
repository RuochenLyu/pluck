#!/usr/bin/env swift
// Generates Pluck.app's icon from the same mark StatusIcon.swift draws.
//
// Drawn in code rather than checked in as a PNG for the reason the menu bar mark is:
// the dash rhythm has to be tuned per size, and one source for the silhouette means the
// menu bar and the Finder icon can never drift apart. Run:
//
//     swift Scripts/make-icon.swift <output.icns>

import AppKit
import Foundation

/// Everything below is authored against a 1024pt canvas and rasterized down.
let canvas: CGFloat = 1024
/// The macOS icon grid: the shape is inset from the canvas, which is the room the system
/// reserves for the shadow it composites behind every icon.
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let plateRadius: CGFloat = 185

/// The 18pt menu bar mark, blown up and centred. Same numbers as `StatusIcon.blob` callers.
let markScale = 600.0 / 18.0
let markOrigin: CGFloat = (canvas - 600) / 2

func marked(_ rect: NSRect) -> NSRect {
    NSRect(
        x: rect.minX * markScale + markOrigin,
        y: rect.minY * markScale + markOrigin,
        width: rect.width * markScale,
        height: rect.height * markScale
    )
}

/// Closed Catmull-Rom curve through six unevenly-radiused samples — copied deliberately
/// from StatusIcon so both renderings are the same silhouette.
func blob(in rect: NSRect) -> NSBezierPath {
    let radii: [CGFloat] = [1.0, 0.80, 0.98, 0.86, 1.0, 0.82]
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let points: [NSPoint] = radii.enumerated().map { index, factor in
        let angle = (Double(index) / Double(radii.count)) * 2 * .pi
        return NSPoint(
            x: center.x + cos(angle) * rect.width / 2 * factor,
            y: center.y + sin(angle) * rect.height / 2 * factor
        )
    }

    let path = NSBezierPath()
    path.move(to: points[0])
    for i in 0..<points.count {
        let p0 = points[(i - 1 + points.count) % points.count]
        let p1 = points[i]
        let p2 = points[(i + 1) % points.count]
        let p3 = points[(i + 2) % points.count]
        path.curve(
            to: p2,
            controlPoint1: NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
            controlPoint2: NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        )
    }
    path.close()
    return path
}

/// `pixels` is the final raster size; the drawing scales to it so a 16pt icon is the same
/// artwork, not a different one.
func render(pixels: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("could not allocate a \(pixels)px bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let scale = CGFloat(pixels) / canvas
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let shape = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)
    // Coral is the app's one accent (product-plan §4.7). The icon is its own "screen", so
    // spending the whole plate on it is within the one-tint-per-screen budget.
    NSGradient(
        colors: [
            NSColor(srgbRed: 1.00, green: 0.52, blue: 0.38, alpha: 1),
            NSColor(srgbRed: 0.94, green: 0.31, blue: 0.28, alpha: 1)
        ]
    )?.draw(in: shape, angle: -78)

    NSColor.white.setFill()
    blob(in: marked(NSRect(x: 2.4, y: 9.8, width: 13.2, height: 7.0))).fill()

    let ghost = blob(in: marked(NSRect(x: 2.4, y: 1.0, width: 13.2, height: 7.0).insetBy(dx: 0.7, dy: 0.7)))
    // The hole the subject was lifted out of. Translucent rather than white so it reads as
    // absence; opaque white would be a second subject.
    NSColor.white.withAlphaComponent(0.85).setStroke()
    ghost.lineWidth = 1.4 * markScale
    ghost.lineCapStyle = .round
    ghost.setLineDash([3.0 * markScale, 2.2 * markScale], count: 2, phase: 0)
    ghost.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode the \(pixels)px icon")
    }
    return png
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.icns>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Pluck-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for point in [16, 32, 128, 256, 512] {
    try render(pixels: point).write(to: iconset.appendingPathComponent("icon_\(point)x\(point).png"))
    try render(pixels: point * 2).write(to: iconset.appendingPathComponent("icon_\(point)x\(point)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", output.path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
