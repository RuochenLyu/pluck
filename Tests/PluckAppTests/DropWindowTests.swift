import AppKit
import XCTest

@testable import PluckApp

/// The main window is the app's drop target, and AppKit finds a destination's abilities by
/// `responds(to:)` probing at drag time — a route the compiler cannot check. These
/// selectors going unanswered is exactly how the drop silently died once already: the
/// methods existed in Swift but carried no ObjC entry point.
@MainActor
final class DropWindowTests: XCTestCase {
    private func makeWindow() -> PluckWindow {
        PluckWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
    }

    func testTheWindowAnswersTheDraggingProbes() {
        let window = makeWindow()
        XCTAssertTrue(window.responds(to: #selector(NSDraggingDestination.draggingEntered(_:))))
        XCTAssertTrue(window.responds(to: #selector(NSDraggingDestination.draggingExited(_:))))
        XCTAssertTrue(window.responds(to: #selector(NSDraggingDestination.draggingEnded(_:))))
        XCTAssertTrue(window.responds(to: #selector(NSDraggingDestination.performDragOperation(_:))))
    }
}
