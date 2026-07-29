import AppKit
import XCTest

@testable import PluckApp

/// What the shelf and the preview panel are made of, at the four places it went wrong.
///
/// Both panels were showing a square base underneath their rounded glass. The lens itself is
/// composited by the window server and cannot be rendered here — but the bug never was the
/// lens. It was the layer stack *inside* it: `NSGlassEffectView.cornerRadius` shapes and
/// lights the glass and promises nothing about clipping what is hosted in `contentView`, and
/// the preview panel's content is a full-bleed checkerboard, which is opaque and square by
/// design (§4.7 — the board is content, so it may not be made translucent to show the glass
/// off). Its corners were landing straight on top of the rounded surface.
///
/// So the assertions are about the layer stack, and they are rendered rather than read: a
/// deliberately opaque content view goes in, the hierarchy is drawn into a bitmap with
/// `cacheDisplay`, and the corner pixels are checked for being transparent. That catches the
/// real failure — content escaping the radius — without needing a window server.
@MainActor
final class PanelBackdropTests: XCTestCase {
    private static let side: CGFloat = 120
    private static let radius: CGFloat = 20

    /// Deliberately the worst case: opaque, square, edge to edge. The preview panel's
    /// checkerboard is exactly this.
    private final class OpaqueSquare: NSView {
        override var isOpaque: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.red.setFill()
            bounds.fill()
        }
    }

    private func rendered(cornerRadius: CGFloat) throws -> NSBitmapImageRep {
        let frame = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        let container = NSView(frame: frame)
        PanelBackdrop.install(content: OpaqueSquare(frame: frame), in: container, cornerRadius: cornerRadius)
        container.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: frame))
        // Cleared first: `bitmapImageRepForCachingDisplay` hands back uninitialised memory,
        // and a corner that happens to start at zero would pass this test without the fix.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        frame.fill(using: .copy)
        NSGraphicsContext.restoreGraphicsState()

        container.cacheDisplay(in: frame, to: bitmap)
        return bitmap
    }

    /// The regression, at the pixel the user was looking at. Two points in from the corner is
    /// well outside a 20pt radius, and well inside the square the content used to draw.
    func testTheCornersAreTransparent() throws {
        let bitmap = try rendered(cornerRadius: Self.radius)
        let inset = 2
        let far = bitmap.pixelsWide - 1 - inset
        for point in [(inset, inset), (far, inset), (inset, far), (far, far)] {
            let colour = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1))
            XCTAssertEqual(colour.alphaComponent, 0, accuracy: 0.01, "corner \(point) is not transparent")
        }
    }

    /// And the other half of the claim: the panel is only *missing* at its corners. A clip
    /// that swallowed the middle would pass the test above and fail the product.
    func testTheMiddleIsNot() throws {
        let bitmap = try rendered(cornerRadius: Self.radius)
        let middle = bitmap.pixelsWide / 2
        let colour = try XCTUnwrap(bitmap.colorAt(x: middle, y: middle))
        XCTAssertEqual(colour.alphaComponent, 1, accuracy: 0.01)
    }

    /// The main window passes zero — it is `.titled`, so AppKit clips the content view to the
    /// window frame's own corners, and a radius of ours on top would be a second, slightly
    /// different rounding drawn just inside the first.
    func testAZeroRadiusRoundsNothing() throws {
        let bitmap = try rendered(cornerRadius: 0)
        let colour = try XCTUnwrap(bitmap.colorAt(x: 1, y: 1))
        XCTAssertEqual(colour.alphaComponent, 1, accuracy: 0.01)
    }
}
