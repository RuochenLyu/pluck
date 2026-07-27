import AppKit
import XCTest

@testable import PluckApp

/// The preview opens *from* the shelf, so the one thing this placement may never do is
/// cover it. Tested without a display because the interesting cases are the ones the
/// author's own screen does not have: a status item on the left, a screen too narrow to
/// fit both panels side by side.
@MainActor
final class PreviewPlacementTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 876)
    private let size = CGSize(width: 560, height: 420)

    private func place(shelf: NSRect?) -> NSRect {
        NSRect(origin: PreviewPanelController.origin(for: size, beside: shelf, in: visible), size: size)
    }

    func testSitsLeftOfAShelfOnTheRight() {
        let shelf = NSRect(x: 1050, y: 400, width: 340, height: 452)
        let frame = place(shelf: shelf)
        XCTAssertFalse(frame.intersects(shelf))
        XCTAssertEqual(frame.maxX, shelf.minX - 10)
        // Top edges align: the two panels read as one composition rather than two
        // windows that happen to be near each other.
        XCTAssertEqual(frame.maxY, shelf.maxY)
    }

    func testSitsRightOfAShelfOnTheLeft() {
        let shelf = NSRect(x: 40, y: 400, width: 340, height: 452)
        let frame = place(shelf: shelf)
        XCTAssertFalse(frame.intersects(shelf))
        XCTAssertEqual(frame.minX, shelf.maxX + 10)
    }

    /// A shelf dead centre leaves too little on either side. Something has to give, and it
    /// is the gap, not the screen edge — a panel half off screen is worse than a nudge.
    func testStaysOnScreenWhenNeitherSideFits() {
        let shelf = NSRect(x: 550, y: 400, width: 340, height: 452)
        let frame = place(shelf: shelf)
        XCTAssertTrue(visible.contains(frame))
    }

    func testCentresWhenTheShelfIsClosed() {
        let frame = place(shelf: nil)
        XCTAssertEqual(frame.midX, visible.midX)
        XCTAssertEqual(frame.midY, visible.midY)
    }

    /// A tall cutout next to a shelf that hangs low would otherwise start below the bottom
    /// of the screen — top alignment yields to the edge.
    func testTallPreviewIsPushedDownFromTheTopAlignment() {
        let shelf = NSRect(x: 1050, y: 700, width: 340, height: 150)
        let tall = CGSize(width: 340, height: 560)
        let frame = NSRect(
            origin: PreviewPanelController.origin(for: tall, beside: shelf, in: visible),
            size: tall
        )
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }
}
