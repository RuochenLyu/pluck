import CryptoKit
import Foundation
import XCTest

@testable import PluckKit

/// Serves bytes from disk instead of the network. Every test here is offline by construction.
private final class StubDownloader: ModelDownloading, @unchecked Sendable {
    enum Response {
        case file(URL)
        /// Writes the first `prefix` bytes of the file, then fails — a dropped connection.
        case truncated(URL, prefix: Int)
        case failure(any Error)
    }

    var response: Response
    private(set) var callCount = 0
    private let lock = NSLock()

    init(response: Response) {
        self.response = response
    }

    func download(
        from url: URL,
        into destination: URL,
        onProgress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws {
        let response = lock.withLock {
            callCount += 1
            return self.response
        }

        switch response {
        case .failure(let error):
            throw error
        case .file(let source):
            let bytes = try Data(contentsOf: source)
            try write(bytes, to: destination)
            onProgress(Int64(bytes.count), Int64(bytes.count))
        case .truncated(let source, let prefix):
            let bytes = try Data(contentsOf: source).prefix(prefix)
            try write(Data(bytes), to: destination)
            onProgress(Int64(bytes.count), Int64(bytes.count))
            throw URLError(.networkConnectionLost)
        }
    }

    private func write(_ data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }
}

final class ModelManifestTests: XCTestCase {
    private func manifest(_ json: String) throws -> ModelManifest {
        try ModelManifest(data: Data(json.utf8))
    }

    private let good = """
        {
          "version": 1,
          "models": [
            {
              "id": "birefnet-lite",
              "displayName": "BiRefNet_lite",
              "file": "BiRefNetLite.mlpackage",
              "url": "https://example.com/BiRefNetLite.mlpackage.zip",
              "sha256": "\(String(repeating: "a", count: 64))",
              "bytes": 1234,
              "license": "MIT",
              "source": "https://huggingface.co/ZhengPeng7/BiRefNet_lite",
              "inputSide": 1024
            }
          ]
        }
        """

    func testParsesEveryField() throws {
        let manifest = try manifest(good)
        let model = try XCTUnwrap(manifest["birefnet-lite"])
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(model.displayName, "BiRefNet_lite")
        XCTAssertEqual(model.file, "BiRefNetLite.mlpackage")
        XCTAssertEqual(model.bytes, 1234)
        XCTAssertEqual(model.license, "MIT")
        XCTAssertEqual(model.inputSide, 1024)
        XCTAssertNil(manifest["nope"])
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(try manifest("{ not json")) { error in
            XCTAssertEqual((error as? PluckError)?.kind, .manifestInvalid)
        }
    }

    func testRejectsShortDigest() {
        let bad = good.replacingOccurrences(of: String(repeating: "a", count: 64), with: "abc")
        XCTAssertThrowsError(try manifest(bad)) { error in
            XCTAssertEqual((error as? PluckError)?.kind, .manifestInvalid)
        }
    }

    func testRejectsUnsupportedVersion() {
        let bad = good.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")
        XCTAssertThrowsError(try manifest(bad)) { error in
            XCTAssertEqual((error as? PluckError)?.kind, .manifestInvalid)
        }
    }

    func testRejectsPathInFileName() {
        let bad = good.replacingOccurrences(of: "BiRefNetLite.mlpackage\"", with: "../../evil.mlpackage\"")
        XCTAssertThrowsError(try manifest(bad)) { error in
            XCTAssertEqual((error as? PluckError)?.kind, .manifestInvalid)
        }
    }

    /// The manifest the CLI actually ships must survive its own validator.
    func testShippedManifestIsValid() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models/manifest.json")
        let manifest = try ModelManifest(contentsOf: url)
        XCTAssertEqual(manifest.models.map(\.id), ["birefnet-lite", "birefnet-lite-matting"])
        for model in manifest.models {
            XCTAssertEqual(model.license, "MIT")
            XCTAssertTrue(model.url.absoluteString.hasSuffix(".zip"))
            XCTAssertGreaterThan(model.bytes, 1_000_000)
        }
    }
}

/// Progress arrives on whatever thread the downloader is on, so the log owns a lock.
private final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var phases: [ModelRegistry.Phase] = []

    func record(_ phase: ModelRegistry.Phase) {
        lock.lock()
        defer { lock.unlock() }
        if phases.last != phase { phases.append(phase) }
    }

    var distinct: [ModelRegistry.Phase] {
        lock.lock()
        defer { lock.unlock() }
        return phases
    }
}

final class ModelRegistryTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/tmp")
    private var archive = URL(fileURLWithPath: "/tmp")
    private var digest = ""
    private var size: Int64 = 0

    override func setUp() async throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-registry-\(UUID().uuidString)")
        root = scratch.appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        // A stand-in for the .mlpackage: a directory bundle, zipped exactly the way
        // Scripts/package-models.sh zips the real one.
        let payload = scratch.appendingPathComponent("Fake.mlpackage")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: payload.appendingPathComponent("model.bin"))

        archive = scratch.appendingPathComponent("Fake.mlpackage.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", payload.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int64)
        digest = try ModelRegistry.sha256(of: archive, id: "fake")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func manifest(sha: String? = nil, bytes: Int64? = nil, version: String? = nil) throws -> ModelManifest {
        let versionLine = version.map { "\"version\": \"\($0)\"," } ?? ""
        return try ModelManifest(data: Data("""
            {
              "version": 1,
              "models": [{
                "id": "fake",
                "displayName": "Fake",
                "file": "Fake.mlpackage",
                \(versionLine)
                "url": "https://example.invalid/Fake.mlpackage.zip",
                "sha256": "\(sha ?? digest)",
                "bytes": \(bytes ?? size),
                "license": "MIT",
                "source": "https://example.invalid/fake",
                "inputSide": 1024
              }]
            }
            """.utf8))
    }

    func testInstallsIntoIdDirectory() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(), root: root, downloader: downloader)

        XCTAssertFalse(registry.isInstalled("fake"))
        XCTAssertEqual(registry.availableModels().map(\.id), ["fake"])

        let phases = PhaseLog()
        let installed = try await registry.install("fake") { progress in
            phases.record(progress.phase)
        }

        XCTAssertEqual(installed, root.appendingPathComponent("fake/Fake.mlpackage"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("model.bin").path))
        XCTAssertTrue(registry.isInstalled("fake"))
        XCTAssertEqual(registry.localURL(for: "fake"), installed)
        XCTAssertEqual(registry.installedModels().map(\.id), ["fake"])
        XCTAssertTrue(registry.availableModels().isEmpty)
        XCTAssertEqual(phases.distinct, [.downloading, .verifying, .installing])
    }

    func testSecondInstallIsANoOp() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(), root: root, downloader: downloader)

        try await registry.install("fake")
        try await registry.install("fake")
        XCTAssertEqual(downloader.callCount, 1)

        try await registry.install("fake", force: true)
        XCTAssertEqual(downloader.callCount, 2)
        XCTAssertTrue(registry.isInstalled("fake"))
    }

    func testDigestMismatchInstallsNothing() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(
            manifest: try manifest(sha: String(repeating: "b", count: 64)),
            root: root,
            downloader: downloader
        )

        do {
            try await registry.install("fake")
            XCTFail("a mismatched digest must not install")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelDownloadFailed)
        }
        XCTAssertFalse(registry.isInstalled("fake"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fake").path))
    }

    func testSizeMismatchIsCaughtBeforeHashing() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(bytes: size + 1), root: root, downloader: downloader)

        do {
            try await registry.install("fake")
            XCTFail("a short read must not install")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelDownloadFailed)
        }
        XCTAssertFalse(registry.isInstalled("fake"))
    }

    func testArchiveWithoutTheExpectedBundleIsRejected() async throws {
        let junk = root.deletingLastPathComponent().appendingPathComponent("junk.zip")
        try Data("not a zip".utf8).write(to: junk)
        let bytes = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: junk.path)[.size] as? Int64)
        let digest = try ModelRegistry.sha256(of: junk, id: "fake")

        let downloader = StubDownloader(response: .file(junk))
        let registry = ModelRegistry(
            manifest: try manifest(sha: digest, bytes: bytes),
            root: root,
            downloader: downloader
        )

        do {
            try await registry.install("fake")
            XCTFail("an unusable archive must not install")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelDownloadFailed)
        }
        XCTAssertFalse(registry.isInstalled("fake"))
    }

    func testTransportFailureIsReportedAsDownloadFailure() async throws {
        let downloader = StubDownloader(response: .failure(URLError(.notConnectedToInternet)))
        let registry = ModelRegistry(manifest: try manifest(), root: root, downloader: downloader)

        do {
            try await registry.install("fake")
            XCTFail("a transport error must surface")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelDownloadFailed)
        }
    }

    func testUnknownIdIsMissingNotDownloaded() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(), root: root, downloader: downloader)

        do {
            try await registry.install("ghost")
            XCTFail("an id outside the manifest cannot be installed")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelMissing)
        }
        XCTAssertEqual(downloader.callCount, 0)
    }

    func testRemoveIsIdempotent() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(), root: root, downloader: downloader)

        try await registry.install("fake")
        XCTAssertTrue(try registry.remove("fake"))
        XCTAssertFalse(try registry.remove("fake"))
        XCTAssertFalse(registry.isInstalled("fake"))
    }

    /// The bytes an interrupted attempt did receive are the whole reason resuming exists,
    /// so a transport failure must leave them where the next attempt will look.
    func testInterruptedDownloadKeepsWhatArrived() async throws {
        let downloader = StubDownloader(response: .truncated(archive, prefix: 20))
        let registry = ModelRegistry(manifest: try manifest(), root: root, downloader: downloader)

        do {
            try await registry.install("fake")
            XCTFail("a dropped connection must surface")
        } catch {
            XCTAssertEqual((error as? PluckError)?.kind, .modelDownloadFailed)
        }

        let partial = registry.partialURL(for: "fake")
        let kept = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Int64)
        XCTAssertEqual(kept, 20)
        XCTAssertFalse(registry.isInstalled("fake"))
    }

    /// Bytes that fail the digest are the one thing resuming must never preserve: appending
    /// to them can only ever produce a longer wrong file.
    func testDigestMismatchDiscardsThePartialFile() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(
            manifest: try manifest(sha: String(repeating: "b", count: 64)),
            root: root,
            downloader: downloader
        )

        _ = try? await registry.install("fake")
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.partialURL(for: "fake").path))
    }

    func testSuccessfulInstallLeavesNoPartialBehind() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(), root: root, downloader: downloader)

        try await registry.install("fake")
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.partialURL(for: "fake").path))
    }

    func testDefaultRootIsUnderApplicationSupport() {
        XCTAssertTrue(ModelRegistry.defaultRoot.path.hasSuffix("Application Support/Pluck/Models"))
    }

    func testStreamedDigestMatchesCryptoKit() throws {
        let expected = SHA256.hash(data: try Data(contentsOf: archive))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, expected)
    }

    /// The receipt is what a later manifest is compared against — no receipt, no update
    /// check, so it has to land with the install itself.
    func testInstallWritesAReceiptAndTheModelReadsCurrent() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(version: "1"), root: root, downloader: downloader)
        _ = try await registry.install("fake")

        let receipt = try XCTUnwrap(registry.receipt(for: "fake"))
        XCTAssertEqual(receipt.sha256, digest)
        XCTAssertEqual(receipt.version, "1")
        XCTAssertFalse(registry.isOutdated("fake"))
    }

    /// The whole update mechanism: a newer app ships a manifest whose digest no longer
    /// matches what the receipt says was installed. Purely local — no request is made to
    /// find this out.
    func testAManifestWithNewBytesMarksTheInstallOutdated() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(version: "1"), root: root, downloader: downloader)
        _ = try await registry.install("fake")

        let newer = ModelRegistry(
            manifest: try manifest(sha: String(repeating: "c", count: 64), version: "2"),
            root: root,
            downloader: downloader
        )
        XCTAssertTrue(newer.isOutdated("fake"))
        // Still installed and still usable — outdated is an offer, not a failure state.
        XCTAssertTrue(newer.isInstalled("fake"))
    }

    /// A model installed before receipts existed reads as current: conservative on
    /// purpose, and it starts carrying a receipt on its next install.
    func testAnInstallWithoutAReceiptReadsAsCurrent() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(), root: root, downloader: downloader)
        _ = try await registry.install("fake")
        try FileManager.default.removeItem(at: root.appendingPathComponent("fake/receipt.json"))

        XCTAssertFalse(registry.isOutdated("fake"))
    }

    /// Updating is `install(force:)` — the same download, verify and atomic swap, ending
    /// with a receipt that matches the new manifest.
    func testForceInstallRefreshesTheReceipt() async throws {
        let downloader = StubDownloader(response: .file(archive))
        let registry = ModelRegistry(manifest: try manifest(version: "1"), root: root, downloader: downloader)
        _ = try await registry.install("fake")

        // The "new" release happens to be the same bytes in this test; what matters is
        // that the receipt is rewritten from the manifest being installed from.
        let newer = ModelRegistry(manifest: try manifest(version: "2"), root: root, downloader: downloader)
        _ = try await newer.install("fake", force: true)

        XCTAssertEqual(newer.receipt(for: "fake")?.version, "2")
        XCTAssertFalse(newer.isOutdated("fake"))
    }
}
