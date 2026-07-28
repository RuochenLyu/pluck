import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import PluckApp

/// Dragging a cutout into another app is the one export path with no error channel: the
/// receiving app is not ours to report in, so a drop that produces nothing produces nothing
/// visible either. It therefore may not depend on a file still being there when the mouse
/// comes up — Clear, and eviction off the end of the list, delete these directories while a
/// drag can still be in flight.
final class DragOutTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pluck-drag-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func item(_ bytes: [UInt8], name: String = "hair-01") throws -> RecentItem {
        let file = directory.appendingPathComponent(name).appendingPathExtension("png")
        try Data(bytes).write(to: file)
        return RecentItem(
            fingerprint: PluckService.fingerprint(Data(bytes)),
            thumbnailPNG: Data(bytes),
            fileURL: file,
            originalURL: directory.appendingPathComponent("original.png"),
            suggestedName: name
        )
    }

    private func load(_ provider: NSItemProvider) throws -> Data? {
        let loaded = expectation(description: "the provider to hand over its bytes")
        let box = Box()
        provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
            box.data = data
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        return box.data
    }

    func testTheProviderCarriesTheCutoutAsPNG() throws {
        let provider = try item([1, 2, 3]).dragProvider()
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))
        XCTAssertEqual(try load(provider), Data([1, 2, 3]))
    }

    /// The filename is the whole reason a dropped file beats a dropped bitmap: it is what
    /// Finder writes on the icon.
    func testTheProviderNamesTheFileAfterThePicture() throws {
        XCTAssertEqual(try item([1], name: "IMG_0042").dragProvider().suggestedName, "IMG_0042.png")
    }

    /// The regression. `NSItemProvider(contentsOf:)` only opened the file at the drop, by
    /// which time a Clear a second earlier had already taken it.
    func testADragSurvivesTheEntryBeingDiscardedMidFlight() throws {
        let item = try item([9, 9])
        let provider = item.dragProvider()
        try FileManager.default.removeItem(at: item.fileURL)
        XCTAssertEqual(try load(provider), Data([9, 9]))
    }

    /// A file that was already gone before the gesture started has nothing to offer, and an
    /// empty provider is how a drag says "nothing came of this" — better than bytes that
    /// are not the cutout.
    func testAnAlreadyMissingFileYieldsAnEmptyProvider() {
        let missing = RecentItem(
            fingerprint: "none",
            thumbnailPNG: Data(),
            fileURL: directory.appendingPathComponent("gone.png"),
            originalURL: directory.appendingPathComponent("original.png"),
            suggestedName: "gone"
        )
        XCTAssertTrue(missing.dragProvider().registeredTypeIdentifiers.isEmpty)
    }
}

/// The completion handler runs off the test's thread; this is the smallest thing that can
/// carry a value back across it.
private final class Box: @unchecked Sendable {
    var data: Data?
}
