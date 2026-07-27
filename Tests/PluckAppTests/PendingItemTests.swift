import Foundation
import PluckKit
import XCTest

@testable import PluckApp

private final class MockPasteboard: ImagePasteboard, @unchecked Sendable {
    var stored: (data: Data, name: String)?
    private(set) var written: [Data] = []

    init(stored: (data: Data, name: String)? = nil) {
        self.stored = stored
    }

    func readImage() -> (data: Data, name: String)? { stored }

    func writePNG(_ data: Data) { written.append(data) }
}

private func processed(_ bytes: [UInt8], name: String = "cut") -> ProcessedImage {
    ProcessedImage(
        pngData: Data(bytes),
        thumbnailPNG: Data(bytes),
        originalPNG: Data(bytes),
        width: 2,
        height: 2,
        suggestedName: name
    )
}

/// The placeholder cell is the only thing standing between "I dropped a file" and "a
/// result appeared", so its lifecycle is a state machine, not decoration: it must exist
/// before any work starts, survive until the result lands, and never outlive a failure.
@MainActor
final class PendingItemTests: XCTestCase {
    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        scratch = []
        super.tearDown()
    }

    private func model(
        clipboard: Data? = Data([9]),
        process: @escaping @Sendable (Data, String) async throws -> ProcessedImage
    ) -> AppModel {
        AppModel(
            pasteboard: MockPasteboard(stored: clipboard.map { ($0, "cat") }),
            process: process
        )
    }

    /// Synchronous on purpose — no `await` between the call and the assertion. If the
    /// placeholder only showed up after the first suspension the user would still see the
    /// silent gap this whole mechanism exists to remove.
    func testPlaceholderExistsBeforeTheFirstSuspensionPoint() {
        let model = model { _, _ in processed([1]) }
        XCTAssertTrue(model.pendingItems.isEmpty)
        model.pluckClipboard()
        XCTAssertEqual(model.pendingItems.count, 1)
        XCTAssertEqual(model.pendingItems.first?.state, .running)
        // No thumbnail yet: it costs a decode, which is exactly what has not happened.
        XCTAssertNil(model.pendingItems.first?.thumbnail)
    }

    func testEachDroppedPayloadGetsItsOwnPlaceholder() {
        let model = model { _, _ in processed([1]) }
        model.handleDrop([.data(Data([1])), .data(Data([2])), .data(Data([3]))])
        XCTAssertEqual(model.pendingItems.count, 3)
        XCTAssertEqual(Set(model.pendingItems.map(\.id)).count, 3)
    }

    func testSuccessRetiresThePlaceholderAndLeavesOneRecent() async {
        let model = model { _, _ in processed([1, 2, 3]) }
        model.pluckClipboard()
        await waitUntil("the result to land") { model.recents.items.count == 1 }
        scratch = model.recents.items.map(\.fileURL)
        XCTAssertTrue(model.pendingItems.isEmpty)
        XCTAssertNil(model.highlightedItemID)
    }

    /// The shelf grid renders placeholders and results in one list keyed by this id. If the
    /// result minted a fresh one, SwiftUI would see a delete plus an unrelated insert and
    /// animate the cell moving instead of resolving where the user is looking.
    func testResultInheritsThePlaceholderIdentity() async {
        let model = model { _, _ in processed([7, 7]) }
        model.pluckClipboard()
        let ticket = model.pendingItems.first?.id
        await waitUntil("the result to land") { model.recents.items.count == 1 }
        scratch = model.recents.items.map(\.fileURL)
        XCTAssertEqual(model.recents.items.first?.id, ticket)
    }

    func testFailureMarksThePlaceholderThenRetiresIt() async {
        let model = model { _, _ in throw PluckError.noSubjectDetected }
        model.pluckClipboard()
        await waitUntil("the placeholder to turn red") { model.pendingItems.first?.failure != nil }
        XCTAssertTrue(model.recents.items.isEmpty)
        // Held for a beat, then dropped: a cell that vanished instantly would be
        // indistinguishable from the drop never having registered.
        await waitUntil("the placeholder to fade out", timeout: 8) { model.pendingItems.isEmpty }
    }

    /// An empty clipboard never reaches the engine, but it did claim a cell — that cell
    /// has to come back, or ⌘V on nothing leaves a permanent ghost in the grid.
    func testEmptyClipboardStillRetiresItsPlaceholder() async {
        let model = model(clipboard: nil) { _, _ in
            XCTFail("should not process without input")
            return processed([0])
        }
        model.pluckClipboard()
        XCTAssertEqual(model.pendingItems.count, 1)
        await waitUntil("the placeholder to turn red") { model.pendingItems.first?.failure != nil }
    }

    /// The whole point of the unit: a red rim is not a reason. What the cell carries and
    /// what the status line says have to be the same failure, or the user reads one and
    /// acts on the other.
    func testTheReasonReachesBothTheCellAndTheStatusLine() async {
        let model = model { _, _ in throw PluckError.imageLoadFailed(reason: "not a png") }
        model.pluckClipboard()
        await waitUntil("the failure to land") { model.pendingItems.first?.failure != nil }
        XCTAssertEqual(model.pendingItems.first?.failure, .unreadable)
        XCTAssertEqual(model.statusMessage, PluckFailure.unreadable.message)
    }

    /// "No subject" and "that isn't an image" send the user to different fixes. Collapsing
    /// them into one apology is the behaviour this unit replaced.
    func testDifferentCausesProduceDifferentMessages() async {
        let noSubject = model { _, _ in throw PluckError.noSubjectDetected }
        noSubject.pluckClipboard()
        await waitUntil("the first failure") { noSubject.statusMessage != nil }

        let unreadable = model { _, _ in throw PluckError.imageLoadFailed(reason: "x") }
        unreadable.pluckClipboard()
        await waitUntil("the second failure") { unreadable.statusMessage != nil }

        XCTAssertNotEqual(noSubject.statusMessage, unreadable.statusMessage)
    }

    /// A stale complaint sitting over a drop that is going fine is worse than no status
    /// line at all — the user stops believing the strip.
    func testStartingNewWorkClearsTheOldComplaint() async {
        let pasteboard = MockPasteboard()
        let model = AppModel(pasteboard: pasteboard) { _, _ in processed([1]) }

        model.pluckClipboard()
        await waitUntil("the failure") { model.statusMessage != nil }

        pasteboard.stored = (Data([9]), "cat")
        model.pluckClipboard()
        // Synchronous: the clear belongs to accepting the work, not to finishing it.
        XCTAssertNil(model.statusMessage)
        await waitUntil("the result to land") { model.recents.items.count == 1 }
        scratch = model.recents.items.map(\.fileURL)
    }

    /// The bug users reported as "dragging a cutout back in does nothing": identical
    /// output bytes de-duplicate, which is correct, but it has to be visible.
    func testRePluckingTheSameImageHighlightsTheExistingCellInsteadOfAddingOne() async {
        let model = model { _, _ in processed([1, 2, 3]) }

        model.pluckClipboard()
        await waitUntil("the first result") { model.recents.items.count == 1 }
        scratch = model.recents.items.map(\.fileURL)
        let original = model.recents.items[0].id

        model.pluckClipboard()
        await waitUntil("the duplicate to be folded in") { model.highlightedItemID != nil }
        XCTAssertEqual(model.recents.items.count, 1)
        XCTAssertEqual(model.highlightedItemID, original)
        XCTAssertTrue(model.pendingItems.isEmpty)

        // The flash is transient; a border stuck on forever reads as a selection.
        await waitUntil("the highlight to expire", timeout: 6) { model.highlightedItemID == nil }
    }

    func testClearEmptiesTheGrid() async {
        let model = model { _, _ in processed([4, 5, 6]) }
        model.pluckClipboard()
        await waitUntil("the result to land") { model.recents.items.count == 1 }
        scratch = model.recents.items.map(\.fileURL)
        model.clearRecents()
        XCTAssertTrue(model.recents.items.isEmpty)
        XCTAssertNil(model.highlightedItemID)
    }

    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                return XCTFail("timed out waiting for \(what)", file: file, line: line)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
