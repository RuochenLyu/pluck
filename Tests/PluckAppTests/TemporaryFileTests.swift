import XCTest

@testable import PluckApp

/// The temp copies are cutouts of the user's photos, in the clear. What happens to them
/// when the app is not running is a privacy question, not a housekeeping one.
final class TemporaryFileTests: XCTestCase {
    func testTheSweepTakesEverythingTheLastRunLeftBehind() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PluckSweepTest-\(UUID().uuidString)", isDirectory: true)
        let stale = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: stale.appendingPathComponent("Cutout.png"))

        PluckService.discardOrphanedTemporaryFiles(at: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    /// Called on every launch, including the first one on a fresh machine.
    func testSweepingAnAbsentDirectoryIsNotAnError() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PluckSweepTest-\(UUID().uuidString)", isDirectory: true)
        PluckService.discardOrphanedTemporaryFiles(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    /// The path every drag-out depends on: a real file, under the root the sweep and the
    /// per-item deletion guard both key off, named after the picture rather than "image".
    func testAWrittenCutoutLandsUnderTheRootWithItsOwnName() throws {
        let processed = ProcessedImage(
            pngData: Data("png".utf8),
            thumbnailPNG: Data(),
            originalPNG: Data(),
            width: 1,
            height: 1,
            suggestedName: "hair-01"
        )
        let url = try PluckService.writeTemporaryFile(processed, id: UUID())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        XCTAssertEqual(url.lastPathComponent, "hair-01.png")
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent(), PluckService.temporaryRoot)
        XCTAssertEqual(try Data(contentsOf: url), processed.pngData)
    }
}
