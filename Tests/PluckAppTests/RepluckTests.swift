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

/// Every pass appends a byte, so a re-pluck of a cutout is never the same bytes as the
/// cutout it came from — otherwise the fingerprint would fold the two into one entry and
/// the test would be measuring de-duplication instead.
private func onePassMore(_ data: Data, _ name: String, _ engine: any MattingEngine) -> ProcessedImage {
    processed([UInt8](data) + [0], name: name)
}

/// Running one picture through a second engine, and what the grid is allowed to do about it.
///
/// The rules worth pinning down are all about *not* losing things: the first cutout stays,
/// the two stay related, every engine stays on the menu, and switching back to one this
/// picture has already been through re-uses the cutout instead of computing it again. None
/// of it needs Core ML — the engine is injected, and what is being tested is the bookkeeping
/// around it.
@MainActor
final class RepluckTests: XCTestCase {
    private var scratch: [URL] = []

    override func tearDown() async throws {
        for url in scratch {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        scratch = []
    }

    private func model(
        catalog: EngineCatalog = EngineCatalog(registry: nil),
        process: @escaping @Sendable (Data, String, any MattingEngine) async throws -> ProcessedImage
    ) -> AppModel {
        AppModel(
            pasteboard: MockPasteboard(),
            engines: EngineProvider(catalog: catalog),
            process: process
        )
    }

    /// Two models with nothing on disk, so the menu has something to offer and something to
    /// price. Never touched by anything here that could download.
    private func catalogWithTwoModels() throws -> EngineCatalog {
        let manifest = try ModelManifest(data: Data("""
            {
              "version": 1,
              "models": [
                {
                  "id": "birefnet-lite", "displayName": "BiRefNet_lite",
                  "file": "A.mlpackage", "url": "https://example.invalid/a.zip",
                  "sha256": "\(String(repeating: "a", count: 64))", "bytes": 83000000,
                  "license": "MIT", "source": "https://example.invalid/a", "inputSide": 1024
                },
                {
                  "id": "birefnet-lite-matting", "displayName": "BiRefNet_lite matting",
                  "file": "B.mlpackage", "url": "https://example.invalid/b.zip",
                  "sha256": "\(String(repeating: "b", count: 64))", "bytes": 82000000,
                  "license": "MIT", "source": "https://example.invalid/b", "inputSide": 1024
                }
              ]
            }
            """.utf8))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-repluck-\(UUID().uuidString)", isDirectory: true)
        return EngineCatalog(registry: ModelRegistry(manifest: manifest, root: root))
    }

    /// A second cutout of one picture through another engine: same lineage, same files — so
    /// a re-pluck of it can still read the original back — different bytes. It stands in for
    /// a re-pluck no unit test can perform, since a second engine means a download and a Core
    /// ML compile.
    private func sibling(of item: RecentItem, engine: String) -> RecentItem {
        RecentItem(
            fingerprint: engine + item.fingerprint,
            thumbnailPNG: item.thumbnailPNG,
            fileURL: item.fileURL,
            originalURL: item.originalURL,
            suggestedName: item.suggestedName,
            engineID: engine,
            sourceID: item.sourceID
        )
    }

    /// An entry with nothing behind it, for the lineage rule — which is arithmetic on three
    /// fields and never opens a file.
    private func fake(engine: String) -> RecentItem {
        RecentItem(
            fingerprint: UUID().uuidString,
            thumbnailPNG: Data(),
            fileURL: URL(fileURLWithPath: "/dev/null"),
            originalURL: URL(fileURLWithPath: "/dev/null"),
            suggestedName: "cut",
            engineID: engine
        )
    }

    private func firstCutout(_ model: AppModel) async -> RecentItem? {
        await waitUntil("the first cutout") { model.recents.items.count == 1 }
        return model.recents.items.first
    }

    /// The decision this whole feature rests on: lite's decided edge and lite-matting's soft
    /// one are two answers, not two attempts at one. Replacing the entry would make comparing
    /// them cost a re-pluck of whichever was overwritten.
    func testARepluckedCutoutIsFiledBesideTheOriginalRatherThanOverIt() async {
        let model = model(process: onePassMore)
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }

        model.repluck(first, with: EngineCatalog.defaultEngineID)
        await waitUntil("the second cutout") { model.recents.items.count == 2 }
        scratch = model.recents.items.map(\.fileURL)

        XCTAssertTrue(model.recents.items.contains { $0.id == first.id })
        XCTAssertEqual(Set(model.recents.items.map(\.sourceID)), [first.sourceID])
    }

    /// The pane that asked is the pane that should end up showing the answer.
    func testTheNewCutoutIsHandedToTheInspector() async {
        let model = model(process: onePassMore)
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }

        model.repluck(first, with: EngineCatalog.defaultEngineID)
        await waitUntil("the second cutout") { model.recents.items.count == 2 }
        scratch = model.recents.items.map(\.fileURL)

        XCTAssertTrue(model.showsPreview)
        XCTAssertNotEqual(model.previewedID, first.id)
        XCTAssertEqual(model.previewedID, model.recents.items.first?.id)
    }

    /// Named an engine, got Vision: for a drop that is the right trade, and here it is a
    /// duplicate of the cutout the user is already looking at.
    func testAnEngineThatCannotBeLoadedFailsTheJobInsteadOfSilentlyUsingVision() async {
        let model = model(process: onePassMore)
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }
        scratch = [first.fileURL]

        model.repluck(first, with: "birefnet-lite")
        await waitUntil("the failure") { model.pendingItems.contains { $0.failure != nil } }

        XCTAssertEqual(model.recents.items.count, 1)
        XCTAssertEqual(model.status?.text, PluckFailure.modelUnavailable.message)
    }

    /// A second click on the same menu entry while the first is still running would queue the
    /// same 1–2 seconds of work twice and file two identical cutouts.
    func testASecondRequestForTheSamePictureIsIgnoredWhileOneIsRunning() async {
        let gate = Gate()
        // Only the second pass is held: the first drop has to get through, or there is no
        // cutout to ask for a re-pluck of. One byte of input means the drop, two means the
        // re-pluck feeding it the first cutout's original back in.
        let model = model { data, name, _ in
            if data.count > 1 { await gate.wait() }
            return processed([UInt8](data) + [0], name: name)
        }
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }

        model.repluck(first, with: EngineCatalog.defaultEngineID)
        await waitUntil("the job to register") { model.isRepluckRunning(first) }
        model.repluck(first, with: EngineCatalog.defaultEngineID)
        XCTAssertEqual(model.pendingItems.count, 1)

        await gate.open()
        await waitUntil("the job to finish") { model.recents.items.count == 2 }
        scratch = model.recents.items.map(\.fileURL)
    }

    // MARK: - What the switcher offers

    /// Every engine, every time, with the one that made this cutout ticked. A list that lost
    /// an entry once it had been used could never be learned, and it answered "what is left
    /// to try" when the question in front of the user is "what am I looking at".
    func testTheSwitcherListsEveryEngineAndTicksTheCurrentOne() async throws {
        let model = model(catalog: try catalogWithTwoModels(), process: onePassMore)
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }
        scratch = [first.fileURL]

        let options = await model.engineOptions(for: first)

        XCTAssertEqual(options.map(\.id), [EngineCatalog.defaultEngineID, "birefnet-lite", "birefnet-lite-matting"])
        XCTAssertEqual(
            options.map(\.label),
            [L.s("Apple Vision"), L.s("Clean Cut"), L.s("Fine Edges")]
        )
        XCTAssertEqual(options.filter(\.isCurrent).map(\.id), [EngineCatalog.defaultEngineID])
        // Not installed, so the parenthetical is what the click will cost in bytes.
        XCTAssertEqual(options.first { $0.id == "birefnet-lite" }?.hint, EngineLabels.megabytes(83000000))
        XCTAssertNil(options.first?.hint)
    }

    /// The tick follows the cutout, not the preference: opening the other half of a lineage
    /// must move it.
    func testTheTickFollowsTheCutoutBeingLookedAt() async throws {
        let model = model(catalog: try catalogWithTwoModels(), process: onePassMore)
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }
        scratch = [first.fileURL]
        let sibling = sibling(of: first, engine: "birefnet-lite")

        let options = await model.engineOptions(for: sibling)

        XCTAssertEqual(options.filter(\.isCurrent).map(\.id), ["birefnet-lite"])
    }

    // MARK: - Switching

    /// Lineage, engine, and still in the grid — all three, or it is not the cutout that
    /// answers the question.
    func testTheSiblingLookupMatchesOnLineageAndEngineTogether() {
        let a = fake(engine: EngineCatalog.defaultEngineID)
        let mine = sibling(of: a, engine: "birefnet-lite")
        let stranger = fake(engine: "birefnet-lite")

        XCTAssertEqual(AppModel.sibling(of: a, engine: "birefnet-lite", in: [stranger, mine])?.id, mine.id)
        XCTAssertNil(AppModel.sibling(of: a, engine: "birefnet-lite-matting", in: [stranger, mine]))
        XCTAssertNil(AppModel.sibling(of: a, engine: "birefnet-lite", in: [stranger]))
    }

    /// The point of the switcher: two cutouts of one photo are both on the shelf already, so
    /// flipping between them to compare edges is a panel swap and not a second pluck.
    func testSwitchingToAnEngineTheGridAlreadyHoldsShowsItWithoutComputingAnything() async {
        let model = model(process: onePassMore)
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }
        scratch = [first.fileURL]
        // A second entry of the same lineage from another engine, standing in for a re-pluck
        // no test can run: loading a real model is a download and a Core ML compile.
        let other = sibling(of: first, engine: "birefnet-lite")
        model.recents.insert(other)

        model.showEngine(EngineCatalog.defaultEngineID, for: other)

        XCTAssertEqual(model.previewedID, first.id)
        XCTAssertTrue(model.showsPreview)
        XCTAssertTrue(model.pendingItems.isEmpty)
        XCTAssertEqual(model.recents.items.count, 2)
    }

    /// And the other path: a combination the grid has never held is work, and goes through
    /// the same re-pluck as before.
    func testSwitchingToAnEngineWithNoResultYetComputesOne() async {
        let model = model(process: onePassMore)
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }
        // Its own lineage, so Vision's cutout of the *other* picture is not a sibling of it.
        let lone = RecentItem(
            fingerprint: "lone", thumbnailPNG: Data(), fileURL: first.fileURL,
            originalURL: first.originalURL, suggestedName: "cut", engineID: "birefnet-lite"
        )
        model.recents.insert(lone)

        model.showEngine(EngineCatalog.defaultEngineID, for: lone)
        await waitUntil("the computed cutout") { model.recents.items.count == 3 }
        scratch = model.recents.items.map(\.fileURL)

        XCTAssertEqual(model.recents.items.first?.sourceID, lone.sourceID)
    }

    /// Picking the engine that is already ticked is not a request for anything.
    func testChoosingTheCurrentEngineDoesNothing() async {
        let model = model(process: onePassMore)
        model.handleDrop([.data(Data([1]))])
        guard let first = await firstCutout(model) else { return }
        scratch = [first.fileURL]

        model.showEngine(first.engineID, for: first)

        XCTAssertNil(model.previewedID)
        XCTAssertFalse(model.showsPreview)
        XCTAssertTrue(model.pendingItems.isEmpty)
        XCTAssertEqual(model.recents.items.count, 1)
    }

    /// Order is a fact about the choice, not about the disk: a model finishing its download
    /// must not make the menu reshuffle under the pointer.
    func testTheOrderIsTheBuiltInEngineThenTheManifestsOwn() async throws {
        let provider = EngineProvider(catalog: try catalogWithTwoModels())
        let ids = await provider.options.map(\.id)
        XCTAssertEqual(ids, [EngineCatalog.defaultEngineID, "birefnet-lite", "birefnet-lite-matting"])
    }

    // MARK: - Copy

    /// The labels are the whole point of the redesign: `BiRefNet_lite` tells the user
    /// nothing about which of their photographs it is for.
    func testEveryEngineHasAHumanNameAndASentence() {
        for id in [EngineCatalog.defaultEngineID, "birefnet-lite", "birefnet-lite-matting"] {
            XCTAssertFalse(EngineLabels.name(id).contains("birefnet"))
            XCTAssertNotNil(EngineLabels.blurb(id))
        }
    }

    /// A model the manifest gains tomorrow renders under its own name rather than as a blank
    /// row — copy nobody has written is not a reason to hide the engine.
    func testAnUnknownEngineFallsBackToTheManifestName() {
        XCTAssertEqual(EngineLabels.name("future", fallback: "BiRefNet_future"), "BiRefNet_future")
        XCTAssertNil(EngineLabels.blurb("future"))
    }

    /// Vision is the default and most of the list; marking it would print one word on every
    /// row, which is how a label stops being read.
    func testOnlyANonDefaultEngineMarksItsResults() {
        XCTAssertNil(EngineLabels.mark(EngineCatalog.defaultEngineID))
        XCTAssertEqual(EngineLabels.mark("birefnet-lite-matting"), L.s("Fine Edges"))
    }

    /// A duration is a claim about the user's machine, and this app has never measured one.
    /// The parenthetical is now reserved for the download, which is a fact about the bytes.
    func testOnlyAnEngineThatStillHasToBeDownloadedCarriesAParenthetical() {
        let installed = AppModel.EngineOption(
            id: "a", label: "Clean Cut", hint: nil, installed: true, isCurrent: true
        )
        let missing = AppModel.EngineOption(
            id: "b", label: "Fine Edges", hint: "83 MB", installed: false, isCurrent: false
        )
        XCTAssertEqual(installed.menuTitle, "Clean Cut")
        XCTAssertTrue(missing.menuTitle.contains("83 MB"))
        XCTAssertTrue(missing.menuTitle.hasPrefix("Fine Edges"))
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

private final class MockPasteboard: ImagePasteboard, @unchecked Sendable {
    func readImage() -> (data: Data, name: String)? { nil }
    func writePNG(_ data: Data) {}
}

private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
