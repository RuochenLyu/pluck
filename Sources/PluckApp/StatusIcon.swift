import AppKit
import Foundation

/// The mark from prototypes/p6-icon.png concept 1: a solid organic blob lifted clear of
/// the dashed outline it left behind. Drawn in code rather than shipped as a PDF so the
/// dash rhythm can be tuned to the 18pt menu bar size — at that scale a scaled-down
/// vector turns the outline into mush.
enum StatusIcon {
    static let size = NSSize(width: 18, height: 18)

    static let idle = make(liftedIsOutline: true)
    static let done = make(liftedIsOutline: false)

    private static func make(liftedIsOutline: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let solid = blob(in: NSRect(x: 2.4, y: 9.8, width: 13.2, height: 7.0))
            NSColor.black.setFill()
            solid.fill()

            let ghost = blob(in: NSRect(x: 2.4, y: 1.0, width: 13.2, height: 7.0).insetBy(dx: 0.7, dy: 0.7))
            if liftedIsOutline {
                NSColor.black.setStroke()
                ghost.lineWidth = 1.4
                ghost.lineCapStyle = .round
                // ~5 dashes around the perimeter: fewer reads as a solid blob, more turns to noise.
                ghost.setLineDash([3.0, 2.2], count: 2, phase: 0)
                ghost.stroke()
            } else {
                NSColor.black.setFill()
                ghost.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L.s("Pluck")
        return image
    }

    /// Closed Catmull-Rom curve through six unevenly-radiused samples — organic, but
    /// deterministic, so both blobs are the same silhouette.
    private static func blob(in rect: NSRect) -> NSBezierPath {
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
}
