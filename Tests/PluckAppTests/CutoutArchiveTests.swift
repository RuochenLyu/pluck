import PluckKit
import XCTest

@testable import PluckApp

/// The archive is where the privacy promise and the persistence promise meet: these files
/// are cutouts of the user's photographs, so what survives a quit — and what does not —
/// has to be exactly what the preference says.
final class CutoutArchiveTests: XCTestCase {
    private var root: URL!
    private var archive: CutoutArchive!

    override func setUp() {
        super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PluckArchiveTest-\(UUID().uuidString)", isDirectory: true)
        archive = CutoutArchive(root: root, keepsIndex: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func processed(_ byte: UInt8, name: String = "hair-01") -> ProcessedImage {
        ProcessedImage(
            pngData: Data([byte, 1]),
            thumbnailPNG: Data([byte, 2]),
            originalPNG: Data([byte, 3]),
            width: 4,
            height: 2,
            suggestedName: name
        )
    }

    /// The cutout keeps the picture's name because that is the filename Finder shows the
    /// moment the cell is dragged out; the other two are fixed, since nothing user-facing
    /// ever sees them.
    func testStoreLaysDownThreeFilesUnderTheItemsOwnDirectory() throws {
        let id = UUID()
        let item = try archive.store(processed(9), id: id)

        XCTAssertEqual(item.fileURL.lastPathComponent, "hair-01.png")
        XCTAssertEqual(item.fileURL.deletingLastPathComponent().lastPathComponent, id.uuidString)
        XCTAssertEqual(item.pngData(), Data([9, 1]))
        XCTAssertEqual(item.originalPNG(), Data([9, 3]))
        XCTAssertEqual(item.thumbnailPNG, Data([9, 2]))
        XCTAssertEqual(item.pixelWidth, 4)
    }

    func testAStoredItemComesBackInOrderAfterARestart() throws {
        let first = try archive.store(processed(1), id: UUID())
        let second = try archive.store(processed(2, name: "dog"), id: UUID())
        archive.writeIndex([second, first])

        let restored = archive.load(limit: 20)

        XCTAssertEqual(restored.map(\.id), [second.id, first.id])
        XCTAssertEqual(restored.map(\.suggestedName), ["dog", "hair-01"])
        XCTAssertEqual(restored.first?.pngData(), Data([2, 1]))
        // Thumbnails are the one thing loaded eagerly — the grid draws them immediately.
        XCTAssertEqual(restored.last?.thumbnailPNG, Data([1, 2]))
    }

    /// A crash between `store` and `writeIndex` leaves a directory nothing points at.
    /// Nobody would ever delete it: the index is the only list, and it does not mention it.
    func testDirectoriesTheIndexDoesNotMentionAreSweptOnLoad() throws {
        let kept = try archive.store(processed(1), id: UUID())
        let orphan = try archive.store(processed(2), id: UUID())
        archive.writeIndex([kept])

        XCTAssertEqual(archive.load(limit: 20).map(\.id), [kept.id])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: orphan.fileURL.deletingLastPathComponent().path)
        )
    }

    /// The sweep acts only on the word of an index that decoded. A missing or corrupt
    /// index means "we know nothing", and deleting on ignorance is how one bad byte in a
    /// JSON file becomes an empty archive at the next launch.
    func testAMissingOrCorruptIndexSweepsNothing() throws {
        let a = try archive.store(processed(1), id: UUID())
        let b = try archive.store(processed(2), id: UUID())

        XCTAssertTrue(archive.load(limit: 20).isEmpty, "no index, so nothing to restore")
        for item in [a, b] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: item.fileURL.path),
                "an absent index must not read as \u{201C}everything is an orphan\u{201D}"
            )
        }

        try Data("not json".utf8).write(to: archive.root.appendingPathComponent("index.json"))
        XCTAssertTrue(archive.load(limit: 20).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.fileURL.path))
    }

    /// The index says what the order was; the directory says what exists. Where they
    /// disagree the directory wins — an entry whose PNG was deleted underneath us must not
    /// come back as a cell whose every button fails.
    func testAnEntryWhoseFileIsGoneIsDropped() throws {
        let alive = try archive.store(processed(1), id: UUID())
        let deleted = try archive.store(processed(2), id: UUID())
        archive.writeIndex([deleted, alive])
        try FileManager.default.removeItem(at: deleted.fileURL)

        XCTAssertEqual(archive.load(limit: 20).map(\.id), [alive.id])
    }

    /// The compatibility rail. An index written by a version that had never heard of engines
    /// is the user's whole history, and a record type that throws on a missing key would turn
    /// it into "no index" — which is an archive that empties itself on the launch after an
    /// update. Absent means Vision (that is all the app could produce then) and a lineage of
    /// one (nothing on disk claims to be a re-pluck of it).
    func testAnIndexFromBeforeEnginesWereRecordedStillLoads() throws {
        let id = UUID()
        let item = try archive.store(processed(1), id: id)
        let legacy = """
            {"version":1,"items":[{
              "id":"\(id.uuidString)",
              "fingerprint":"\(item.fingerprint)",
              "file":"hair-01.png",
              "name":"hair-01",
              "width":4,
              "height":2,
              "createdAt":"2026-07-27T10:00:00Z"
            }]}
            """
        try Data(legacy.utf8).write(to: archive.root.appendingPathComponent("index.json"))

        let restored = archive.load(limit: 20)

        XCTAssertEqual(restored.map(\.id), [id], "one missing key must not cost the history")
        XCTAssertEqual(restored.first?.engineID, EngineCatalog.defaultEngineID)
        XCTAssertEqual(restored.first?.sourceID, id)
    }

    /// A re-pluck files a second cutout of one picture, and the two have to still be one
    /// picture after a restart — that is the whole basis of "engines this image has not been
    /// through" in the preview menu.
    func testTheEngineAndTheLineageSurviveARestart() throws {
        let source = try archive.store(processed(1), id: UUID())
        let again = try archive.store(
            processed(2, name: "hair-01"),
            id: UUID(),
            engineID: "birefnet-lite-matting",
            sourceID: source.sourceID
        )
        archive.writeIndex([again, source])

        let restored = archive.load(limit: 20)

        XCTAssertEqual(restored.map(\.engineID), ["birefnet-lite-matting", EngineCatalog.defaultEngineID])
        XCTAssertEqual(Set(restored.map(\.sourceID)), [source.id])
    }

    func testLoadHonoursTheCap() throws {
        let items = try (1...5).map { try archive.store(processed(UInt8($0), name: "n\($0)"), id: UUID()) }
        archive.writeIndex(items.reversed())

        XCTAssertEqual(archive.load(limit: 3).count, 3)
    }

    /// Flipping the history preference mid-session leaves both kinds of entry in one grid.
    /// Recording the session ones would produce an index full of paths under `/tmp` that
    /// the next launch has already swept.
    func testTheIndexOnlyRecordsEntriesLivingUnderThisRoot() throws {
        let mine = try archive.store(processed(1), id: UUID())
        let elsewhere = try CutoutArchive(root: root.appendingPathComponent("other"), keepsIndex: false)
            .store(processed(2), id: UUID())
        archive.writeIndex([elsewhere, mine])

        XCTAssertEqual(archive.load(limit: 20).map(\.id), [mine.id])
    }

    /// `/tmp` keeps no index on purpose: a restart would find a directory of anonymous
    /// UUIDs and no reason to trust any of it.
    func testASessionArchiveRestoresNothing() throws {
        let session = CutoutArchive(root: root, keepsIndex: false)
        let item = try session.store(processed(1), id: UUID())
        session.writeIndex([item])

        XCTAssertEqual(session.load(limit: 20).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))
    }

    func testDiscardEverythingTakesTheWholeRoot() throws {
        _ = try archive.store(processed(1), id: UUID())
        archive.discardEverything()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testSweepingAnAbsentRootIsNotAnError() {
        archive.discardEverything()
        archive.discardEverything()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    /// The safety rail on per-entry deletion: an item only ever names a directory directly
    /// under one of the two real roots, so a hand-built URL — a bug, or a restored index
    /// from a future version — deletes nothing at all.
    func testDiscardRefusesDirectoriesOutsideTheKnownRoots() throws {
        let victim = root.appendingPathComponent("not-an-archive", isDirectory: true)
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        let item = RecentItem(
            fingerprint: "f",
            thumbnailPNG: Data(),
            fileURL: victim.appendingPathComponent("cut.png"),
            originalURL: victim.appendingPathComponent("original.png"),
            suggestedName: "cut"
        )

        CutoutArchive.discard([item])

        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
    }

    func testDiscardRemovesAnEntrysWholeDirectoryUnderARealRoot() throws {
        let item = try CutoutArchive.session.store(processed(1), id: UUID())
        let directory = item.fileURL.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))

        CutoutArchive.discard([item])

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    /// Not a cosmetic detail: `<tmp>/Pluck` is what the launch sweep deletes, and
    /// Application Support is what it must never touch.
    func testTheTwoRootsAreWhereTheyClaimToBe() {
        XCTAssertEqual(CutoutArchive.session.root.lastPathComponent, "Pluck")
        XCTAssertTrue(CutoutArchive.session.root.path.hasPrefix(NSTemporaryDirectory()))
        XCTAssertFalse(CutoutArchive.session.keepsIndex)
        XCTAssertTrue(CutoutArchive.history.root.path.contains("Application Support/Pluck/History"))
        XCTAssertTrue(CutoutArchive.history.keepsIndex)
    }
}
