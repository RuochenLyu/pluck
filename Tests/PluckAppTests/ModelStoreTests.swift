import CryptoKit
import Foundation
import PluckKit
import XCTest

@testable import PluckApp

/// Hands over bytes from disk, or refuses to. No test here touches the network.
private final class StubDownloader: ModelDownloading, @unchecked Sendable {
    enum Response {
        case file(URL)
        case failure(any Error)
        /// Blocks until cancelled, which is the only way to observe the Cancel button.
        case hang
    }

    let response: Response

    init(_ response: Response) {
        self.response = response
    }

    func download(
        from url: URL,
        into destination: URL,
        onProgress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws {
        switch response {
        case .failure(let error):
            throw error
        case .hang:
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        case .file(let source):
            let bytes = try Data(contentsOf: source)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try bytes.write(to: destination)
            onProgress(Int64(bytes.count), Int64(bytes.count))
        }
    }
}

@MainActor
final class ModelStoreTests: XCTestCase {
    private var scratch = URL(fileURLWithPath: "/tmp")
    private var root = URL(fileURLWithPath: "/tmp")
    private var archive = URL(fileURLWithPath: "/tmp")
    private var digest = ""
    private var size: Int64 = 0
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-models-\(UUID().uuidString)")
        root = scratch.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let payload = scratch.appendingPathComponent("Fake.mlpackage")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: payload.appendingPathComponent("model.bin"))
        archive = scratch.appendingPathComponent("Fake.mlpackage.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", payload.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()
        size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int64)
        digest = SHA256.hash(data: try Data(contentsOf: archive))
            .map { String(format: "%02x", $0) }.joined()

        suite = "PluckModelsTest-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: scratch)
    }

    private func store(_ response: StubDownloader.Response) throws -> ModelStore {
        let manifest = try ModelManifest(data: Data("""
            {
              "version": 1,
              "models": [{
                "id": "fake",
                "displayName": "Fake",
                "file": "Fake.mlpackage",
                "url": "https://example.invalid/Fake.mlpackage.zip",
                "sha256": "\(digest)",
                "bytes": \(size),
                "license": "MIT",
                "source": "https://example.invalid/fake",
                "inputSide": 1024
              }]
            }
            """.utf8))
        return ModelStore(
            registry: ModelRegistry(manifest: manifest, root: root, downloader: StubDownloader(response)),
            engines: EngineProvider(catalog: EngineCatalog(registry: nil))
        )
    }

    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "timed out waiting for \(what)")
    }

    func testAManifestModelStartsOutAvailable() throws {
        let store = try store(.file(archive))
        XCTAssertEqual(store.rows.map(\.id), ["fake"])
        XCTAssertEqual(store.rows.first?.state, .available)
        XCTAssertTrue(store.installedIDs.isEmpty)
    }

    func testDownloadEndsInstalled() async throws {
        let store = try store(.file(archive))
        store.download("fake")
        await waitUntil("the install") { store.rows.first?.state == .installed }
        XCTAssertEqual(store.installedIDs, ["fake"])
        XCTAssertTrue(store.registry?.isInstalled("fake") == true)
    }

    /// The reason has to reach the row: a download that stops with the button back where it
    /// started reads as a button that does nothing.
    func testAFailedDownloadKeepsTheReasonOnTheRow() async throws {
        let store = try store(.failure(URLError(.notConnectedToInternet)))
        store.download("fake")
        await waitUntil("the failure") {
            if case .failed = store.rows.first?.state { return true }
            return false
        }
        guard case .failed(let reason) = store.rows.first?.state else { return XCTFail("not failed") }
        XCTAssertFalse(reason.isEmpty)
        // Still offerable: the usual cause is the network and the usual fix is retrying.
        XCTAssertFalse(store.installedIDs.contains("fake"))
    }

    func testCancelPutsTheRowBackWithoutInstalling() async throws {
        let store = try store(.hang)
        store.download("fake")
        await waitUntil("the download to start") {
            if case .downloading = store.rows.first?.state { return true }
            return false
        }
        store.cancel("fake")
        await waitUntil("the row to settle") { store.rows.first?.state == .available }
        XCTAssertFalse(store.registry?.isInstalled("fake") == true)
    }

    /// A second Download press while one is running would start a second install of the
    /// same id into the same directory.
    func testDownloadIsIgnoredWhileOneIsAlreadyRunning() async throws {
        let store = try store(.hang)
        store.download("fake")
        await waitUntil("the download to start") {
            if case .downloading = store.rows.first?.state { return true }
            return false
        }
        store.download("fake")
        if case .downloading = store.rows.first?.state {} else { XCTFail("the row left the downloading state") }
        store.cancel("fake")
    }

    func testReloadDoesNotInterruptADownloadInFlight() async throws {
        let store = try store(.hang)
        store.download("fake")
        await waitUntil("the download to start") {
            if case .downloading = store.rows.first?.state { return true }
            return false
        }
        store.reload()
        if case .downloading = store.rows.first?.state {} else { XCTFail("reload dropped a live download") }
        store.cancel("fake")
    }

    func testDeleteRemovesTheModelAndTheEnginePreferenceThatPointedAtIt() async throws {
        let store = try store(.file(archive))
        let preferences = Preferences(defaults: defaults)

        store.download("fake")
        await waitUntil("the install") { store.rows.first?.state == .installed }

        preferences.engineID = "fake"
        store.delete("fake", preferences: preferences)

        XCTAssertEqual(store.rows.first?.state, .available)
        XCTAssertFalse(store.registry?.isInstalled("fake") == true)
        XCTAssertEqual(preferences.engineID, EngineCatalog.defaultEngineID)
    }

    /// Deleting a model nobody selected must not quietly change which engine is in use.
    func testDeleteLeavesAnUnrelatedEnginePreferenceAlone() async throws {
        let store = try store(.file(archive))
        let preferences = Preferences(defaults: defaults)
        store.download("fake")
        await waitUntil("the install") { store.rows.first?.state == .installed }

        preferences.engineID = EngineCatalog.defaultEngineID
        store.delete("fake", preferences: preferences)
        XCTAssertEqual(preferences.engineID, EngineCatalog.defaultEngineID)
    }

    func testNoManifestMeansNoRowsAndNoActions() {
        let store = ModelStore(registry: nil, engines: EngineProvider(catalog: EngineCatalog(registry: nil)))
        XCTAssertTrue(store.rows.isEmpty)
        store.download("fake")
        store.delete("fake")
        XCTAssertTrue(store.rows.isEmpty)
    }
}

final class EnginePreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "PluckEngineTest-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testTheDefaultEngineIsTheBuiltInOne() {
        XCTAssertEqual(Preferences(defaults: defaults).engineID, EngineCatalog.defaultEngineID)
    }

    @MainActor
    func testTheChosenEngineOutlivesTheProcess() {
        Preferences(defaults: defaults).engineID = "birefnet-lite"
        XCTAssertEqual(Preferences(defaults: defaults).engineID, "birefnet-lite")
    }

    /// A preference naming a model that is not on this Mac is not an error state: the user
    /// gets Vision and one sentence saying so, and the choice survives for the moment they
    /// install it again.
    func testAnUnloadableEngineFallsBackToVision() async {
        let provider = EngineProvider(catalog: EngineCatalog(registry: nil))
        let resolved = await provider.resolve("birefnet-lite")
        XCTAssertEqual(resolved.fellBackFrom, "birefnet-lite")
        XCTAssertEqual(resolved.engine.id, "vision")
    }

    func testTheBuiltInEngineIsAlwaysReadyAndNeverFallsBack() async {
        let provider = EngineProvider(catalog: EngineCatalog(registry: nil))
        let ready = await provider.isReady(EngineCatalog.defaultEngineID)
        XCTAssertTrue(ready)
        let resolved = await provider.resolve(EngineCatalog.defaultEngineID)
        XCTAssertNil(resolved.fellBackFrom)
    }
}
