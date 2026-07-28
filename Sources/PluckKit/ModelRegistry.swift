import CryptoKit
import Foundation

/// One downloadable model, exactly as `models/manifest.json` describes it.
///
/// `url` is pinned to a specific release asset and `sha256` to that asset's bytes: the
/// manifest ships inside the signed app (and inside the CLI binary), so the signature
/// vouches for the manifest, the manifest vouches for the URL, and the digest vouches for
/// whatever actually came down the wire (product-plan §4.8).
public struct ModelDescriptor: Sendable, Codable, Equatable {
    public let id: String
    public let displayName: String
    /// Name of the model bundle inside the archive, e.g. `BiRefNetLite.mlpackage`.
    public let file: String
    public let url: URL
    public let sha256: String
    public let bytes: Int64
    public let license: String
    public let source: URL
    /// Side length of the square input the converted model expects.
    public let inputSide: Int
}

public struct ModelManifest: Sendable, Equatable, Codable {
    public let version: Int
    public let models: [ModelDescriptor]

    public init(version: Int, models: [ModelDescriptor]) {
        self.version = version
        self.models = models
    }

    public init(data: Data) throws {
        let decoded: ModelManifest
        do {
            decoded = try JSONDecoder().decode(ModelManifest.self, from: data)
        } catch {
            throw PluckError.manifestInvalid(reason: error.localizedDescription)
        }
        try decoded.validate()
        self = decoded
    }

    public init(contentsOf url: URL) throws {
        do {
            try self.init(data: Data(contentsOf: url))
        } catch let error as PluckError {
            throw error
        } catch {
            throw PluckError.manifestInvalid(reason: "\(url.path): \(error.localizedDescription)")
        }
    }

    public subscript(id: String) -> ModelDescriptor? {
        models.first { $0.id == id }
    }

    /// Rejects a manifest that parses but cannot be acted on. A bad digest length or a
    /// duplicate id would otherwise surface much later — as a download that can never
    /// verify, or as an install that silently shadows another model.
    private func validate() throws {
        guard version == 1 else {
            throw PluckError.manifestInvalid(reason: "unsupported manifest version \(version)")
        }
        var seen: Set<String> = []
        for model in models {
            guard !model.id.isEmpty, seen.insert(model.id).inserted else {
                throw PluckError.manifestInvalid(reason: "duplicate or empty model id “\(model.id)”")
            }
            guard model.sha256.count == 64, model.sha256.allSatisfy(\.isHexDigit) else {
                throw PluckError.manifestInvalid(reason: "“\(model.id)”: sha256 must be 64 hex digits")
            }
            guard model.bytes > 0 else {
                throw PluckError.manifestInvalid(reason: "“\(model.id)”: bytes must be positive")
            }
            guard model.inputSide > 0 else {
                throw PluckError.manifestInvalid(reason: "“\(model.id)”: inputSide must be positive")
            }
            guard !model.file.isEmpty, !model.file.contains("/") else {
                throw PluckError.manifestInvalid(reason: "“\(model.id)”: file must be a bare name")
            }
        }
    }
}

/// Installs manifest models under `~/Library/Application Support/Pluck/Models/<id>/`.
///
/// Where the manifest comes from is the caller's problem on purpose: the app reads it from
/// its signed bundle, the CLI from its own resources, tests from a string. A registry that
/// went looking for the manifest itself would be a second, unsigned trust channel.
public struct ModelRegistry: Sendable {
    public enum Phase: Sendable, Equatable {
        case downloading
        case verifying
        case installing
    }

    public struct Progress: Sendable, Equatable {
        public var phase: Phase
        public var completedBytes: Int64
        public var expectedBytes: Int64

        public var fraction: Double? {
            guard expectedBytes > 0 else { return nil }
            return min(1, Double(completedBytes) / Double(expectedBytes))
        }
    }

    public typealias ProgressHandler = @Sendable (Progress) -> Void

    public let manifest: ModelManifest
    public let root: URL
    private let downloader: any ModelDownloading

    public init(
        manifest: ModelManifest,
        root: URL = ModelRegistry.defaultRoot,
        downloader: any ModelDownloading = URLSessionModelDownloader()
    ) {
        self.manifest = manifest
        self.root = root
        self.downloader = downloader
    }

    public static var defaultRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Pluck/Models", isDirectory: true)
    }

    public func descriptor(for id: String) -> ModelDescriptor? { manifest[id] }

    public func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    /// Where an interrupted download is kept until it either finishes or is proved wrong.
    ///
    /// Beside the models rather than in `/tmp` for two reasons: the temporary directory is
    /// swept by the system (and by Pluck's own launch sweep) exactly when a user is most
    /// likely to be resuming — after a quit — and a rename into `Models/` from another
    /// volume is a copy of 94 MB rather than a rename. The leading dot keeps it out of the
    /// way of the `<id>/` directories that mean "installed".
    func partialURL(for id: String) -> URL {
        root.appendingPathComponent(".downloads", isDirectory: true)
            .appendingPathComponent("\(id).partial")
    }

    private func discardPartial(for id: String) {
        let partial = partialURL(for: id)
        try? FileManager.default.removeItem(at: partial)
        try? FileManager.default.removeItem(at: partial.appendingPathExtension("validator"))
    }

    /// The installed model bundle, or nil when it is not on disk.
    public func localURL(for id: String) -> URL? {
        guard let descriptor = manifest[id] else { return nil }
        let url = directory(for: id).appendingPathComponent(descriptor.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func isInstalled(_ id: String) -> Bool { localURL(for: id) != nil }

    public func installedModels() -> [ModelDescriptor] {
        manifest.models.filter { isInstalled($0.id) }
    }

    public func availableModels() -> [ModelDescriptor] {
        manifest.models.filter { !isInstalled($0.id) }
    }

    @discardableResult
    public func remove(_ id: String) throws -> Bool {
        let directory = directory(for: id)
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        try FileManager.default.removeItem(at: directory)
        return true
    }

    /// Downloads, verifies and installs `id`. Idempotent: an already-installed model is
    /// returned untouched unless `force` is set.
    ///
    /// An interrupted call — a dropped connection, a cancelled `Task`, a killed process —
    /// leaves its bytes in `partialURL(for:)`, and the next call continues from there. What
    /// resuming is allowed to change is how long the download takes; what it is not allowed
    /// to change is the answer to "are these the right bytes", which stays exactly one
    /// SHA-256 over the whole finished file.
    @discardableResult
    public func install(
        _ id: String,
        force: Bool = false,
        progress: ProgressHandler? = nil
    ) async throws -> URL {
        guard let descriptor = manifest[id] else { throw PluckError.modelMissing(id: id) }
        if !force, let installed = localURL(for: id) { return installed }

        let archive = partialURL(for: id)
        progress?(Progress(phase: .downloading, completedBytes: 0, expectedBytes: descriptor.bytes))
        do {
            try await downloader.download(from: descriptor.url, into: archive) { received, expected in
                progress?(Progress(
                    phase: .downloading,
                    completedBytes: received,
                    expectedBytes: expected > 0 ? expected : descriptor.bytes
                ))
            }
        } catch {
            // Deliberately not discarded: the bytes on disk are the whole point, and the
            // next attempt will either resume them or reject them on the validator.
            throw PluckError.modelDownloadFailed(id: id, reason: error.localizedDescription)
        }

        progress?(Progress(phase: .verifying, completedBytes: descriptor.bytes, expectedBytes: descriptor.bytes))
        do {
            try verify(archive, against: descriptor)
        } catch {
            // A file that fails the digest will not start passing it by having more bytes
            // appended, so this is the one failure that must not be resumable.
            discardPartial(for: id)
            throw error
        }

        progress?(Progress(phase: .installing, completedBytes: descriptor.bytes, expectedBytes: descriptor.bytes))
        defer { discardPartial(for: id) }
        return try unpack(archive, as: descriptor)
    }

    private func verify(_ archive: URL, against descriptor: ModelDescriptor) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int64) ?? nil
        if let size, size != descriptor.bytes {
            throw PluckError.modelDownloadFailed(
                id: descriptor.id,
                reason: "expected \(descriptor.bytes) bytes, got \(size)"
            )
        }
        let digest = try Self.sha256(of: archive, id: descriptor.id)
        guard digest.caseInsensitiveCompare(descriptor.sha256) == .orderedSame else {
            throw PluckError.modelDownloadFailed(
                id: descriptor.id,
                reason: "SHA256 mismatch (expected \(descriptor.sha256), got \(digest))"
            )
        }
    }

    /// Streamed rather than `Data(contentsOf:)`: the archives are ~100 MB and the whole
    /// point of hashing is to distrust the file, including its size.
    static func sha256(of file: URL, id: String) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch {
            throw PluckError.modelDownloadFailed(id: id, reason: error.localizedDescription)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `.mlpackage` is a directory bundle, so the release asset is a zip. Foundation has no
    /// public zip reader on macOS (`AppleArchive` speaks .aar, and the NSFileCoordinator
    /// trick is a documented accident), and `/usr/bin/ditto` is both what packaged the
    /// asset (Scripts/package-models.sh) and the only unpacker that preserves the bundle's
    /// structure and extended attributes. Same tool on both ends, no third-party code.
    private func unpack(_ archive: URL, as descriptor: ModelDescriptor) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, staging.path]
        ditto.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        ditto.standardError = errors
        do {
            try ditto.run()
        } catch {
            throw PluckError.modelDownloadFailed(id: descriptor.id, reason: error.localizedDescription)
        }
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            let detail = String(decoding: stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PluckError.modelDownloadFailed(
                id: descriptor.id,
                reason: "could not unpack the archive\(detail.isEmpty ? "" : ": \(detail)")"
            )
        }

        let payload = staging.appendingPathComponent(descriptor.file)
        guard fileManager.fileExists(atPath: payload.path) else {
            throw PluckError.modelDownloadFailed(
                id: descriptor.id,
                reason: "archive does not contain \(descriptor.file)"
            )
        }

        // Move the whole staging directory into place in one rename: a half-populated
        // model directory would read as "installed" on the next launch.
        let destination = directory(for: descriptor.id)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        return destination.appendingPathComponent(descriptor.file)
    }
}
