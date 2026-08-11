#!/usr/bin/env swift
// Assembles Pluck.app's icon from the layered artwork in Packaging/icon/.
//
// The layers (a warm-cream gradient ground, a photo card with a cat-shaped hole, and the
// coral cat that stepped out of it) were generated per docs/prototypes/icon-brief.md
// appendix 2 and picked in docs/prototypes/icon-concepts/. This script owns the flat
// composite: layer placement tuned against the real Dock (2026-08-11), Big Sur icon grid
// (824pt rounded rect on a 1024 canvas), every icns size from one artwork.
//
// The same three layers are the input for the Icon Composer version (.icon, system-
// rendered Liquid Glass) — keep them in sync; this composite is what ships in the icns.
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

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let layers = repoRoot.appendingPathComponent("Packaging/icon")

func layer(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: layers.appendingPathComponent(name)) else {
        FileHandle.standardError.write(Data("missing layer: Packaging/icon/\(name)\n".utf8))
        exit(1)
    }
    return image
}

let background = layer("layer-background-cream.png")
let card = layer("layer-card.png")
let cat = layer("layer-cat.png")

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

    // Everything clips to the plate: the icns carries the icon's own rounded rect, and
    // the layers are full-bleed artwork.
    NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius).addClip()

    background.draw(in: NSRect(x: plate.minX, y: plate.minY, width: plate.width, height: plate.height))

    // Placement tuned in the Dock, not on a canvas: the card fills most of the plate with
    // its centre nudged low-left; the cat rides the card's upper-right edge, close enough
    // to the hole it left that the two read as one event. The draw rects are oversized
    // because each source PNG carries its own transparent margin.
    let cardSide: CGFloat = canvas * 0.97
    card.draw(in: NSRect(x: 455 - cardSide / 2, y: 465 - cardSide / 2, width: cardSide, height: cardSide))

    let catSide: CGFloat = canvas * 0.74
    cat.draw(in: NSRect(x: 668 - catSide / 2, y: 630 - catSide / 2, width: catSide, height: catSide))

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
