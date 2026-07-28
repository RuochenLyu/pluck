import Foundation
import XCTest

@testable import PluckKit

/// `Scripts/serve-models.py`, started on a free port and torn down with the test.
///
/// A real HTTP server rather than a `URLProtocol` stub because what is under test *is* the
/// HTTP: whether `Range`/`If-Range` are sent, whether a 206 is appended and a 200 is not.
/// A stub that answered those headers would only be asserting that the test agrees with
/// itself. It is still an offline test — 127.0.0.1, a directory this test wrote, and a
/// process this test owns.
private final class LocalModelServer {
    /// Everything the server said, written from the drain thread and read from the test.
    private final class Transcript: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""

        func append(_ chunk: String) { lock.withLock { text += chunk } }
        var contents: String { lock.withLock { text } }
    }

    let port: Int
    private let process: Process
    private let stderr = Pipe()
    private let log = Transcript()

    /// Nil when there is no python3 to run, so the caller can skip rather than fail.
    init?(root: URL, flakyAfter: Int? = nil) {
        guard let python = Self.python else { return nil }
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/serve-models.py")

        process = Process()
        process.executableURL = python
        var arguments = [script.path, root.path, "0"]
        if let flakyAfter { arguments += ["--flaky", "\(flakyAfter)"] }
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        guard (try? process.run()) != nil else { return nil }

        // Drained on a background queue for as long as the server lives: an undrained pipe
        // fills at 64 KB and blocks the server mid-response, which would look exactly like
        // the dropped connection this suite is trying to control.
        let handle = stderr.fileHandleForReading
        let log = self.log
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                log.append(String(decoding: data, as: UTF8.self))
            }
        }

        // The port is on the first line, because port 0 means the kernel picked it.
        let deadline = Date().addingTimeInterval(10)
        var announced: Int?
        while Date() < deadline, announced == nil {
            let first = log.contents
                .split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            if first.hasPrefix("listening 127.0.0.1:"), let value = Int(first.dropFirst("listening 127.0.0.1:".count)) {
                announced = value
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        guard let announced else {
            process.terminate()
            return nil
        }
        port = announced
    }

    var transcript: String { log.contents }

    func url(for file: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(file)")!
    }

    /// Polled rather than `waitUntilExit()`, which spins the calling thread's run loop and
    /// has been seen not to come back from an XCTest teardown.
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private static var python: URL? {
        ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

final class ResumeDownloadTests: XCTestCase {
    private var scratch = URL(fileURLWithPath: "/tmp")
    private var served = URL(fileURLWithPath: "/tmp")
    private var root = URL(fileURLWithPath: "/tmp")
    private var digest = ""
    private var size: Int64 = 0
    private var server: LocalModelServer?

    private static let assetName = "Fake.mlpackage.zip"

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-resume-\(UUID().uuidString)")
        served = scratch.appendingPathComponent("served", isDirectory: true)
        root = scratch.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: served, withIntermediateDirectories: true)
        try packAsset(seed: 1)
    }

    override func tearDownWithError() throws {
        server?.stop()
        server = nil
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Builds a `.mlpackage`-shaped zip of ~300 KB. Incompressible bytes on purpose: the
    /// tests cut the transfer at a byte offset, so the archive's size has to be predictable.
    private func packAsset(seed: UInt64) throws {
        let payload = scratch.appendingPathComponent("Fake.mlpackage")
        try? FileManager.default.removeItem(at: payload)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)

        var state = seed &* 6_364_136_223_846_793_005 &+ 1
        var bytes = [UInt8]()
        bytes.reserveCapacity(300_000)
        for _ in 0..<300_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes.append(UInt8(truncatingIfNeeded: state >> 33))
        }
        try Data(bytes).write(to: payload.appendingPathComponent("weights.bin"))

        let archive = served.appendingPathComponent(Self.assetName)
        try? FileManager.default.removeItem(at: archive)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", payload.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int64)
        digest = try ModelRegistry.sha256(of: archive, id: "fake")
    }

    private func start(flakyAfter: Int? = nil) throws -> LocalModelServer {
        guard let server = LocalModelServer(root: served, flakyAfter: flakyAfter) else {
            throw XCTSkip("no python3 to run Scripts/serve-models.py")
        }
        self.server = server
        return server
    }

    private func registry(_ server: LocalModelServer) throws -> ModelRegistry {
        let manifest = try ModelManifest(data: Data("""
            {
              "version": 1,
              "models": [{
                "id": "fake",
                "displayName": "Fake",
                "file": "Fake.mlpackage",
                "url": "\(server.url(for: Self.assetName).absoluteString)",
                "sha256": "\(digest)",
                "bytes": \(size),
                "license": "MIT",
                "source": "https://example.invalid/fake",
                "inputSide": 1024
              }]
            }
            """.utf8))
        return ModelRegistry(manifest: manifest, root: root)
    }

    func testDownloadsAndVerifiesInOnePass() async throws {
        let server = try start()
        let registry = try registry(server)

        let installed = try await registry.install("fake")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("weights.bin").path))
        XCTAssertTrue(registry.isInstalled("fake"))
        XCTAssertFalse(server.transcript.contains("206"))
    }

    /// The server cuts every connection after 120 KB, so a 300 KB asset can only arrive by
    /// resuming. Each attempt must pick up where the last one stopped, and the digest over
    /// the joined pieces must still be the digest of the whole file.
    func testResumesAcrossDroppedConnections() async throws {
        let server = try start(flakyAfter: 120_000)
        let registry = try registry(server)

        var attempts = 0
        var carried: Int64 = 0
        var installed: URL?
        while installed == nil, attempts < 10 {
            attempts += 1
            do {
                installed = try await registry.install("fake")
            } catch {
                let partial = registry.partialURL(for: "fake")
                let held = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? 0
                carried = max(carried, held)
            }
        }

        XCTAssertGreaterThan(attempts, 1, "a 300 KB asset cut at 120 KB cannot arrive in one attempt")
        // Not asserted per attempt: whether a *particular* interrupted attempt keeps its
        // bytes depends on how the peer's socket was torn down, and a test that pins that
        // down is testing the kernel. What has to hold is that some attempt carried bytes
        // forward and the next one continued from them rather than starting over.
        XCTAssertGreaterThan(carried, 0, "an interrupted attempt must leave its bytes behind")
        let url = try XCTUnwrap(installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("weights.bin").path))
        XCTAssertTrue(server.transcript.contains("206"), "the retry must have been a range request")
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.partialURL(for: "fake").path))
    }

    /// A partial left over from an asset that has since been replaced. `If-Range` fails, the
    /// server sends the whole entity with a 200, and the client must throw away what it was
    /// holding rather than append to it — appending would produce a file of the right length
    /// and the wrong bytes, which is exactly what the digest is there to refuse.
    func testStaleValidatorRestartsTheDownload() async throws {
        let server = try start()
        let registry = try registry(server)

        let partial = registry.partialURL(for: "fake")
        try FileManager.default.createDirectory(
            at: partial.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x5A, count: 100_000).write(to: partial)
        try Data("\"a-tag-from-an-older-release\"".utf8)
            .write(to: partial.appendingPathExtension("validator"))

        let installed = try await registry.install("fake")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("weights.bin").path))
        XCTAssertFalse(server.transcript.contains("206"), "a stale validator must not be resumed from")
        XCTAssertTrue(server.transcript.contains("200"))
    }

    /// Same story one layer down, with no registry involved: the downloader is what decides
    /// a resume is unsafe, and it decides it from the sidecar alone.
    func testDownloaderRefusesToResumeWithoutAValidator() async throws {
        let server = try start()
        let destination = scratch.appendingPathComponent("downloads/fake.partial")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x5A, count: 100_000).write(to: destination)

        try await URLSessionModelDownloader().download(
            from: server.url(for: Self.assetName),
            into: destination
        ) { _, _ in }

        XCTAssertEqual(try ModelRegistry.sha256(of: destination, id: "fake"), digest)
    }
}
