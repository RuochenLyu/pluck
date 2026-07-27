import Foundation
import PluckKit
import XCTest

@testable import PluckApp

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

/// The batch counter is the main window's only honest progress signal, so what it counts
/// matters more than how it looks: a bar that stalls at 4/5 because the fifth file was
/// corrupt tells the user the app hung.
@MainActor
final class BatchTests: XCTestCase {
    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        scratch = []
        super.tearDown()
    }

    private func model(
        process: @escaping @Sendable (Data, String) async throws -> ProcessedImage
    ) -> AppModel {
        AppModel(pasteboard: MockPasteboard(), process: process)
    }

    func testAMultiFileDropCountsEveryFile() {
        let model = model { _, _ in processed([1]) }
        model.handleDrop([.data(Data([1])), .data(Data([2])), .data(Data([3]))])
        XCTAssertEqual(model.batch?.total, 3)
        XCTAssertEqual(model.batch?.done, 0)
    }

    func testTheCounterReachesFull() async {
        let model = model { data, _ in processed([data[0], 0]) }
        model.handleDrop([.data(Data([1])), .data(Data([2])), .data(Data([3]))])
        await waitUntil("the batch to drain") { model.batch?.done == 3 }
        scratch = model.recents.items.map(\.fileURL)
        XCTAssertEqual(model.batch?.fraction, 1)
    }

    /// The case the count exists for. One bad file among three used to leave the bar short
    /// of the end for as long as the window stayed open, which reads as "still working".
    func testAFailureStillCountsAsDone() async {
        let model = model { data, _ in
            guard data[0] != 2 else { throw PluckError.noSubjectDetected }
            return processed([data[0], 0])
        }
        model.handleDrop([.data(Data([1])), .data(Data([2])), .data(Data([3]))])
        await waitUntil("the batch to drain") { model.batch?.done == 3 }
        scratch = model.recents.items.map(\.fileURL)
        XCTAssertEqual(model.recents.items.count, 2)
    }

    /// De-duplication resolves a job without producing an entry. It is still a file the
    /// user handed over and got an answer about.
    func testADuplicateCountsAsDone() async {
        let model = model { _, _ in processed([7, 7]) }
        model.handleDrop([.data(Data([1]))])
        await waitUntil("the first result") { model.recents.items.count == 1 }
        scratch = model.recents.items.map(\.fileURL)

        model.handleDrop([.data(Data([7, 7]))])
        await waitUntil("the duplicate to fold in") { model.highlightedItemID != nil }
        XCTAssertEqual(model.batch?.total, 1)
        XCTAssertEqual(model.batch?.done, 1)
    }

    /// A drop that lands while the previous one is still running joins it; one that lands
    /// after the list has drained starts over. Otherwise the second drop of three files
    /// would show "3 of 6".
    func testADropAfterTheListDrainsStartsAFreshCount() async {
        let model = model { data, _ in processed([data[0], 0]) }
        model.handleDrop([.data(Data([1])), .data(Data([2]))])
        await waitUntil("the first batch") { model.batch?.done == 2 }
        model.handleDrop([.data(Data([3]))])
        XCTAssertEqual(model.batch?.total, 1)
        XCTAssertEqual(model.batch?.done, 0)
        await waitUntil("the second batch") { model.batch?.done == 1 }
        scratch = model.recents.items.map(\.fileURL)
    }

    func testAnEmptyBatchIsZeroRatherThanNotANumber() {
        XCTAssertEqual(BatchProgress(total: 0, done: 0).fraction, 0)
    }

    // MARK: - Export naming

    /// Two folders each holding an `IMG_0042.jpg` is the ordinary case. Overwriting the
    /// first cutout with the second would destroy work the user cannot get back.
    func testExportNeverOverwritesAnExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pluck-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = AppModel.availableURL(in: directory, name: "cat")
        XCTAssertEqual(first.lastPathComponent, "cat.png")
        try Data([1]).write(to: first)

        let second = AppModel.availableURL(in: directory, name: "cat")
        XCTAssertEqual(second.lastPathComponent, "cat 2.png")
        try Data([2]).write(to: second)

        XCTAssertEqual(AppModel.availableURL(in: directory, name: "cat").lastPathComponent, "cat 3.png")
        XCTAssertEqual(try Data(contentsOf: first), Data([1]), "the first export was overwritten")
    }

    // MARK: - Row names

    /// The batch list is a list of *files*. A row that cannot say which one it is leaves
    /// the user counting positions to work out which of forty failed.
    func testADroppedFileIsNamedAfterItself() {
        let name = DroppedPayload.file(URL(fileURLWithPath: "/tmp/holiday/IMG_0042.jpg")).displayName
        XCTAssertEqual(name, "IMG_0042.jpg")
    }

    func testARawBitmapSaysWhereItCameFromRatherThanInventingAName() {
        XCTAssertEqual(DroppedPayload.data(Data([1])).displayName, L.s("Dropped image"))
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

/// Drops never read the clipboard, but `AppModel` needs one; this one has nothing to give.
private final class MockPasteboard: ImagePasteboard, @unchecked Sendable {
    func readImage() -> (data: Data, name: String)? { nil }
    func writePNG(_ data: Data) {}
}
