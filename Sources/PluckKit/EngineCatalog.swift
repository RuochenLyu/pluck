import Foundation

/// One engine the caller could ask for, and whether asking would work right now.
public struct EngineDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let summary: String
    /// Ships with the binary — nothing to download.
    public let builtIn: Bool
    public let installed: Bool
    /// The manifest entry behind this engine, or nil for the built-in one. The app's
    /// Models pane needs the size, the license and the source; the CLI does not.
    public let model: ModelDescriptor?

    public init(id: String, summary: String, builtIn: Bool, installed: Bool, model: ModelDescriptor? = nil) {
        self.id = id
        self.summary = summary
        self.builtIn = builtIn
        self.installed = installed
        self.model = model
    }
}

/// What `--model` (and the app's engine picker) will accept right now, on this machine.
///
/// `vision` is always there, and every manifest model becomes usable the moment it is on
/// disk. Lives in PluckKit rather than in either shell because both need exactly this
/// answer, and two implementations of "which engines are usable" is two chances to disagree
/// with each other about what the user has installed.
///
/// The manifest is read from a signed bundle's resources and never from the working
/// directory: a manifest picked up from wherever the binary happened to run would be a way
/// to point the downloader anywhere (product-plan §4.8).
public struct EngineCatalog: Sendable {
    public static let defaultEngineID = "vision"

    public static let vision = EngineDescriptor(
        id: defaultEngineID,
        summary: "Apple Vision foreground segmentation (macOS 14+)",
        builtIn: true,
        installed: true
    )

    /// Nil when the bundle carries no readable manifest — the built-in engine still works,
    /// which is why this is a degraded catalog rather than a failed initializer.
    public let registry: ModelRegistry?

    public init(registry: ModelRegistry?) {
        self.registry = registry
    }

    public static func bundled(
        in bundle: Bundle,
        root: URL = ModelRegistry.defaultRoot,
        downloader: any ModelDownloading = URLSessionModelDownloader()
    ) -> EngineCatalog {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json"),
              let manifest = try? ModelManifest(contentsOf: url)
        else { return EngineCatalog(registry: nil) }
        return EngineCatalog(registry: ModelRegistry(manifest: manifest, root: root, downloader: downloader))
    }

    public var installed: [EngineDescriptor] {
        [Self.vision] + (registry?.installedModels().map { Self.descriptor(for: $0, installed: true) } ?? [])
    }

    /// In the manifest, not on disk.
    public var available: [EngineDescriptor] {
        registry?.availableModels().map { Self.descriptor(for: $0, installed: false) } ?? []
    }

    public var all: [EngineDescriptor] { installed + available }

    public func descriptor(for id: String) -> EngineDescriptor? {
        all.first { $0.id == id }
    }

    private static func descriptor(for model: ModelDescriptor, installed: Bool) -> EngineDescriptor {
        EngineDescriptor(
            id: model.id,
            summary: "\(model.displayName) via Core ML, \(model.inputSide)px (\(model.license))",
            builtIn: false,
            installed: installed,
            model: model
        )
    }

    /// One fallible lookup rather than a nil for "unknown" beside a throw for "absent".
    ///
    /// The caller cannot act on the difference — both are exit 3 with the same advice —
    /// and the split let the CLI plan's `descriptor(for:)` check and this one drift apart.
    /// It also has to stay genuinely reachable: the plan sees the model installed, but a
    /// `pluck models rm` (or a cache wipe) between the plan and the load leaves the
    /// manifest entry standing with nothing on disk under it.
    public func engine(for id: String) async throws -> any MattingEngine {
        if id == Self.vision.id { return VisionEngine() }
        guard let registry, let url = registry.localURL(for: id) else {
            throw PluckError.modelMissing(id: id)
        }
        return try await CoreMLEngine.load(id: id, modelURL: url)
    }

    public var availabilityMessage: String {
        "installed models: \(installed.map(\.id).joined(separator: ", "))"
    }
}
