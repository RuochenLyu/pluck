import AppKit
import XCTest

@testable import PluckApp

/// The shelf is the app's only window, and an `LSUIElement` app has no Dock icon to fall
/// back on — so "off screen" and "does not exist" are the same thing to a user. Tested
/// without a display because the cases that matter are the ones the author's own screen
/// does not have: a status item pushed to the far right, and no status item at all.
@MainActor
final class ShelfPlacementTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 876)
    private let size = ShelfView.size

    private func place(under anchor: NSRect?) -> NSRect {
        NSRect(origin: ShelfPanelController.origin(for: size, under: anchor, in: visible), size: size)
    }

    func testHangsCentredUnderTheStatusItem() {
        let anchor = NSRect(x: 700, y: 852, width: 24, height: 24)
        let frame = place(under: anchor)
        XCTAssertEqual(frame.midX, anchor.midX)
        XCTAssertEqual(frame.maxY, anchor.minY - 6)
        XCTAssertTrue(visible.contains(frame))
    }

    /// Status items live at the right end of the bar, so this is the common case, not the
    /// edge case: centring on the icon would put half the shelf past the screen.
    func testClampsInsteadOfOverhangingTheRightEdge() {
        let anchor = NSRect(x: 1416, y: 852, width: 24, height: 24)
        let frame = place(under: anchor)
        XCTAssertTrue(visible.contains(frame))
        XCTAssertLessThan(frame.midX, anchor.midX)
    }

    func testClampsInsteadOfOverhangingTheLeftEdge() {
        let anchor = NSRect(x: 0, y: 852, width: 24, height: 24)
        XCTAssertTrue(visible.contains(place(under: anchor)))
    }

    /// The reachability fallback: a full menu bar, a notch, or Bartender has swallowed the
    /// icon, so there is nothing to hang from. Top centre is the one spot on screen that
    /// whatever hid the icon cannot also be covering.
    func testFallsBackToTopCentreWithNoAnchor() {
        let frame = place(under: nil)
        XCTAssertEqual(frame.midX, visible.midX)
        XCTAssertEqual(frame.maxY, visible.maxY - 8)
        XCTAssertTrue(visible.contains(frame))
    }

    /// A display whose menu bar is not at the top of the global coordinate space: the
    /// anchor and the visible frame both move, and the shelf has to follow both.
    func testStaysWithinASecondaryDisplay() {
        let second = NSRect(x: -1680, y: 300, width: 1680, height: 1000)
        let anchor = NSRect(x: -300, y: 1276, width: 24, height: 24)
        let frame = NSRect(
            origin: ShelfPanelController.origin(for: size, under: anchor, in: second),
            size: size
        )
        XCTAssertTrue(second.contains(frame))
    }

    /// Degenerate but reachable in practice — a small external display in portrait, or a
    /// scaled resolution below the shelf's own height. Clamping must not invert the frame.
    func testDoesNotInvertOnAScreenSmallerThanTheShelf() {
        let tiny = NSRect(x: 0, y: 0, width: 300, height: 300)
        let frame = NSRect(
            origin: ShelfPanelController.origin(for: size, under: nil, in: tiny),
            size: size
        )
        XCTAssertEqual(frame.minX, tiny.minX + 8)
        XCTAssertEqual(frame.minY, tiny.minY + 8)
    }
}
