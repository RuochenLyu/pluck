#!/usr/bin/env swift
// Generates the styled (non-photographic) QA fixtures: flat illustration, line art,
// pixel art, sticker. All original program output (or composites of this repo's own
// ImageGen icon layers) — freely redistributable by construction, no external sources.
//
//     swift Scripts/make-styled-fixtures.swift
//
// Deterministic: re-running overwrites the same five files in Tests/Fixtures.
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let out = repoRoot.appendingPathComponent("Tests/Fixtures")

func draw(_ width: Int, _ height: Int, _ body: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    body()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func saveJPEG(_ rep: NSBitmapImageRep, _ name: String) {
    let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!
    try! data.write(to: out.appendingPathComponent(name))
    print("wrote", name)
}

// MARK: illo-01 — the repo's own ImageGen cat on a programmatic dusk scene
do {
    let cat = NSImage(contentsOf: repoRoot.appendingPathComponent("Packaging/icon/layer-cat.png"))!
    let rep = draw(1600, 1200) {
        NSGradient(colors: [
            NSColor(srgbRed: 0.99, green: 0.80, blue: 0.60, alpha: 1),
            NSColor(srgbRed: 0.93, green: 0.52, blue: 0.42, alpha: 1)
        ])!.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1200), angle: -90)
        NSColor(srgbRed: 0.99, green: 0.93, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 260, y: 780, width: 180, height: 180)).fill()
        NSColor(srgbRed: 0.85, green: 0.42, blue: 0.38, alpha: 1).setFill()
        let hills = NSBezierPath()
        hills.move(to: NSPoint(x: 0, y: 330))
        hills.curve(to: NSPoint(x: 800, y: 400), controlPoint1: NSPoint(x: 260, y: 470), controlPoint2: NSPoint(x: 560, y: 330))
        hills.curve(to: NSPoint(x: 1600, y: 300), controlPoint1: NSPoint(x: 1080, y: 470), controlPoint2: NSPoint(x: 1360, y: 300))
        hills.line(to: NSPoint(x: 1600, y: 0)); hills.line(to: NSPoint(x: 0, y: 0)); hills.close(); hills.fill()
        cat.draw(in: NSRect(x: 480, y: 140, width: 760, height: 760))
    }
    saveJPEG(rep, "illo-01.jpg")
}

// MARK: illo-02 — flat geometric character in a shape city
do {
    let rep = draw(1600, 1200) {
        NSGradient(colors: [
            NSColor(srgbRed: 0.72, green: 0.86, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.88, green: 0.94, blue: 0.98, alpha: 1)
        ])!.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1200), angle: -90)
        // background blocks (buildings)
        for (x, w, h, tone) in [(80, 260, 620, 0.72), (380, 200, 780, 0.62), (1180, 240, 700, 0.68), (1440, 160, 560, 0.75)] {
            NSColor(white: tone, alpha: 1).setFill()
            NSRect(x: x, y: 0, width: w, height: h).fill()
        }
        // character: round head, capsule body, stubby legs
        let body = NSColor(srgbRed: 0.29, green: 0.56, blue: 0.85, alpha: 1)
        body.setFill()
        NSBezierPath(roundedRect: NSRect(x: 690, y: 260, width: 260, height: 380), xRadius: 120, yRadius: 120).fill()
        NSColor(srgbRed: 0.98, green: 0.80, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 700, y: 600, width: 240, height: 240)).fill()
        NSColor(srgbRed: 0.24, green: 0.20, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 760, y: 700, width: 26, height: 26)).fill()
        NSBezierPath(ovalIn: NSRect(x: 850, y: 700, width: 26, height: 26)).fill()
        body.setFill()
        NSRect(x: 725, y: 180, width: 70, height: 100).fill()
        NSRect(x: 845, y: 180, width: 70, height: 100).fill()
    }
    saveJPEG(rep, "illo-02.jpg")
}

// MARK: lineart-01 — black outline drawing on white, no fills
do {
    let rep = draw(1600, 1200) {
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1600, height: 1200).fill()
        NSColor.black.setStroke()
        // a simple house with a tree, pure strokes
        let house = NSBezierPath()
        house.lineWidth = 10
        house.appendRect(NSRect(x: 560, y: 300, width: 480, height: 360))
        house.move(to: NSPoint(x: 520, y: 660))
        house.line(to: NSPoint(x: 800, y: 900))
        house.line(to: NSPoint(x: 1080, y: 660))
        house.appendRect(NSRect(x: 740, y: 300, width: 120, height: 200))
        house.appendRect(NSRect(x: 620, y: 480, width: 110, height: 100))
        house.appendRect(NSRect(x: 880, y: 480, width: 110, height: 100))
        house.stroke()
        let tree = NSBezierPath()
        tree.lineWidth = 10
        tree.move(to: NSPoint(x: 1220, y: 300))
        tree.line(to: NSPoint(x: 1220, y: 560))
        tree.appendOval(in: NSRect(x: 1120, y: 540, width: 200, height: 240))
        tree.stroke()
    }
    saveJPEG(rep, "lineart-01.jpg")
}

// MARK: pixel-01 — pixel-art creature on a pixel sky
do {
    let grid = 16, cell = 60
    // 16x16 sprite: a simple orange cat face
    let sprite: [String] = [
        "................",
        "...X........X...",
        "..XX........XX..",
        "..XOX......XOX..",
        "..XOOXXXXXXOOX..",
        "..XOOOOOOOOOOX..",
        "..XOOOOOOOOOOX..",
        "..XOWWOOOOWWOX..",
        "..XOWBOOOOBWOX..",
        "..XOOOOOOOOOOX..",
        "..XOOOOPPOOOOX..",
        "..XOOOOOOOOOOX..",
        "...XOOOOOOOOX...",
        "....XXXXXXXX....",
        "................",
        "................"
    ]
    let rep = draw(grid * cell, grid * cell) {
        for row in 0..<grid {
            for col in 0..<grid {
                let shade = (row + col) % 2 == 0 ? 0.62 : 0.66
                NSColor(srgbRed: shade * 0.7, green: shade, blue: 1.0, alpha: 1).setFill()
                NSRect(x: col * cell, y: row * cell, width: cell, height: cell).fill()
            }
        }
        for (r, line) in sprite.enumerated() {
            for (c, ch) in line.enumerated() {
                let color: NSColor?
                switch ch {
                case "X": color = NSColor(srgbRed: 0.20, green: 0.12, blue: 0.08, alpha: 1)
                case "O": color = NSColor(srgbRed: 0.95, green: 0.55, blue: 0.25, alpha: 1)
                case "W": color = .white
                case "B": color = .black
                case "P": color = NSColor(srgbRed: 0.95, green: 0.45, blue: 0.55, alpha: 1)
                default: color = nil
                }
                if let color {
                    color.setFill()
                    NSRect(x: c * cell, y: (grid - 1 - r) * cell, width: cell, height: cell).fill()
                }
            }
        }
    }
    saveJPEG(rep, "pixel-01.jpg")
}

// MARK: sticker-01 — white-stroked sticker fruit on a flat ground
do {
    let rep = draw(1600, 1200) {
        NSColor(srgbRed: 0.36, green: 0.42, blue: 0.62, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1600, height: 1200).fill()
        // sticker: pear with thick white border
        let pear = NSBezierPath()
        pear.move(to: NSPoint(x: 800, y: 260))
        pear.curve(to: NSPoint(x: 620, y: 520), controlPoint1: NSPoint(x: 640, y: 260), controlPoint2: NSPoint(x: 600, y: 400))
        pear.curve(to: NSPoint(x: 760, y: 820), controlPoint1: NSPoint(x: 640, y: 660), controlPoint2: NSPoint(x: 700, y: 760))
        pear.curve(to: NSPoint(x: 840, y: 820), controlPoint1: NSPoint(x: 790, y: 850), controlPoint2: NSPoint(x: 810, y: 850))
        pear.curve(to: NSPoint(x: 980, y: 520), controlPoint1: NSPoint(x: 900, y: 760), controlPoint2: NSPoint(x: 960, y: 660))
        pear.curve(to: NSPoint(x: 800, y: 260), controlPoint1: NSPoint(x: 1000, y: 400), controlPoint2: NSPoint(x: 960, y: 260))
        pear.close()
        NSColor.white.setStroke()
        pear.lineWidth = 44
        pear.stroke()
        NSColor(srgbRed: 0.65, green: 0.82, blue: 0.36, alpha: 1).setFill()
        pear.fill()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 800, y: 840))
        stem.curve(to: NSPoint(x: 840, y: 950), controlPoint1: NSPoint(x: 800, y: 890), controlPoint2: NSPoint(x: 815, y: 930))
        stem.lineWidth = 24
        NSColor(srgbRed: 0.45, green: 0.32, blue: 0.20, alpha: 1).setStroke()
        stem.stroke()
    }
    saveJPEG(rep, "sticker-01.jpg")
}
print("all fixtures written")
