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

    /// The corner the user dragged the panel to is the corner it comes back to, even though
    /// the next cutout is a different shape and the frame therefore grows from a different
    /// bottom edge. Remembering the origin instead would slide the panel down the screen.
    func testARememberedCornerSurvivesAResize() {
        let topLeft = NSPoint(x: 300, y: 800)
        let tall = CGSize(width: 340, height: 560)
        let first = NSRect(origin: PreviewPanelController.origin(for: size, keeping: topLeft, in: visible), size: size)
        let second = NSRect(origin: PreviewPanelController.origin(for: tall, keeping: topLeft, in: visible), size: tall)
        XCTAssertEqual(first.minX, topLeft.x)
        XCTAssertEqual(first.maxY, topLeft.y)
        XCTAssertEqual(second.minX, topLeft.x)
        XCTAssertEqual(second.maxY, topLeft.y)
    }

    /// Displays get unplugged and resolutions change. A position remembered from a screen
    /// that no longer exists has to yield to the one that does.
    func testARememberedCornerOffTheScreenIsClampedBackIn() {
        let frame = NSRect(
            origin: PreviewPanelController.origin(for: size, keeping: NSPoint(x: 2400, y: 200), in: visible),
            size: size
        )
        XCTAssertTrue(visible.contains(frame))
    }

    // MARK: - Noticing the drag

    /// The panel is placed by us and moved by the user, and only the second of those is an
    /// answer worth remembering. The frame not matching where we put it is the only
    /// evidence available — a borderless panel's drag is AppKit's, not ours.
    func testAPanelStillWhereItWasPutDownIsNotARememberedPosition() {
        let placed = NSPoint(x: 100, y: 200)
        let frame = NSRect(origin: placed, size: size)
        XCTAssertNil(PreviewPanelController.movedTopLeft(of: frame, placedAt: placed))
    }

    /// Top-left, not the AppKit origin: the panel is resized per image and grows upward from
    /// its bottom edge, so remembering the bottom would make it walk down the screen.
    func testAMovedPanelIsRememberedByItsTopLeftCorner() {
        let frame = NSRect(x: 140, y: 260, width: size.width, height: size.height)
        let moved = PreviewPanelController.movedTopLeft(of: frame, placedAt: NSPoint(x: 100, y: 200))
        XCTAssertEqual(moved, NSPoint(x: frame.minX, y: frame.maxY))
    }

    /// Nothing has been placed yet, so nothing can have been dragged.
    func testAPanelThatWasNeverPlacedRemembersNothing() {
        XCTAssertNil(PreviewPanelController.movedTopLeft(of: NSRect(origin: .zero, size: size), placedAt: nil))
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

    /// The two corner captions say which half is which. They are always up — except when
    /// the wipe handle is about to run one over, which is the only case worth a rule.
    func testBothSideLabelsShowWithTheHandleInTheMiddle() {
        let labels = CutoutPreviewView.labels(at: 0.5)
        XCTAssertTrue(labels.original)
        XCTAssertTrue(labels.cutout)
    }

    /// Handle all the way left: there is no "before" half left to label.
    func testTheOriginalLabelYieldsWhenTheHandleReachesIt() {
        XCTAssertFalse(CutoutPreviewView.labels(at: 0).original)
        XCTAssertTrue(CutoutPreviewView.labels(at: 0).cutout)
    }

    func testTheCutoutLabelYieldsWhenTheHandleReachesIt() {
        XCTAssertFalse(CutoutPreviewView.labels(at: 1).cutout)
        XCTAssertTrue(CutoutPreviewView.labels(at: 1).original)
    }

    /// Never both hidden: whatever the handle is doing, the panel keeps saying what at
    /// least one side of it is.
    func testAtLeastOneLabelSurvivesEveryHandlePosition() {
        for step in 0...20 {
            let labels = CutoutPreviewView.labels(at: CGFloat(step) / 20)
            XCTAssertTrue(labels.original || labels.cutout, "fraction \(CGFloat(step) / 20)")
        }
    }
}
