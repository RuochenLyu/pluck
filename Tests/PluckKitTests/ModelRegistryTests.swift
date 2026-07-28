import CryptoKit
import Foundation
import XCTest

@testable import PluckKit

/// Serves bytes from disk instead of the network. Every test here is offline by construction.
private final class StubDownloader: ModelDownloading, @unchecked Sendable {
    enum Response {
        case file(URL)
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
        onProgress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        let response = lock.withLock {
            callCount += 1
            return self.response
        }

        switch response {
        case .failure(let error):
            throw error
        case .file(let source):
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("stub-download-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: source, to: copy)
            let size = (try FileManager.default.attributesOfItem(atPath: copy.path)[.size] as? Int64) ?? 0
            onProgress(size, size)
            return copy
        }
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

    override func setUpWithError() throws {
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

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func manifest(sha: String? = nil, bytes: Int64? = nil) throws -> ModelManifest {
        try ModelManifest(data: Data("""
            {
              "version": 1,
              "models": [{
                "id": "fake",
                "displayName": "Fake",
                "file": "Fake.mlpackage",
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

    func testDefaultRootIsUnderApplicationSupport() {
        XCTAssertTrue(ModelRegistry.defaultRoot.path.hasSuffix("Application Support/Pluck/Models"))
    }

    func testStreamedDigestMatchesCryptoKit() throws {
        let expected = SHA256.hash(data: try Data(contentsOf: archive))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, expected)
    }
}
