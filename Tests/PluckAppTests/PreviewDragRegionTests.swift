import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import PluckApp

/// A borderless panel only moves where some view claims `mouseDownCanMoveWindow`. Where
/// that region sits is geometry, and the geometry has two ways to be wrong that both look
/// fine in a screenshot: cover the close button and it stops firing, cover the image and
/// the before/after wipe turns into a window move.
///
/// The assertions are on the region's frame rather than on hit-testing, because
/// `NSHostingView.hitTest` needs a live window to consult SwiftUI's own hit-test tree and
/// this process has none.
@MainActor
final class PreviewDragRegionTests: XCTestCase {
    private let side: CGFloat = 400
    private let closeButtonInset: CGFloat = 44

    /// Host coordinates, which SwiftUI keeps flipped: y grows downward from the top edge.
    private func dragRegionFrame() -> NSRect? {
        let item = RecentItem(
            id: UUID(),
            fingerprint: "f",
            pngData: Data([1]),
            thumbnailPNG: Data([1]),
            originalPNG: Data([1]),
            fileURL: URL(fileURLWithPath: "/tmp/pluck-test.png"),
            suggestedName: "shot",
            pixelWidth: 100,
            pixelHeight: 100
        )
        let host = NSHostingView(
            rootView: CutoutPreviewView(item: item, model: AppModel(), onClose: {})
        )
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        host.layoutSubtreeIfNeeded()

        // Deepest first: SwiftUI wraps the representable in a host view of its own, and
        // outside a window every non-opaque `NSView` answers yes to
        // `mouseDownCanMoveWindow` — so the wrapper would match before the real region.
        func find(_ view: NSView) -> NSView? {
            for subview in view.subviews {
                if let found = find(subview) { return found }
            }
            return view !== host && view.mouseDownCanMoveWindow ? view : nil
        }
        return find(host).map { $0.convert($0.bounds, to: host) }
    }

    func testTheTitleStripIsADragRegion() throws {
        let frame = try XCTUnwrap(dragRegionFrame())
        XCTAssertEqual(frame.minX, 0)
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.height, 44)
    }

    /// Stops short of the close button, and only just — the strip has to stay wide enough
    /// to be a plausible thing to grab.
    func testItStopsShortOfTheCloseButton() throws {
        let frame = try XCTUnwrap(dragRegionFrame())
        XCTAssertEqual(frame.maxX, side - closeButtonInset)
    }

    /// Everything below the strip belongs to the wipe, which is the reason this panel
    /// exists at all.
    func testItLeavesTheImageToTheWipe() throws {
        let frame = try XCTUnwrap(dragRegionFrame())
        XCTAssertLessThan(frame.maxY, side / 4)
    }
}
