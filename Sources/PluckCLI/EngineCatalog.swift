import Foundation
import PluckKit

struct EngineDescriptor: Sendable, Equatable {
    let id: String
    let summary: String
    /// Ships with the binary — nothing to download.
    let builtIn: Bool
    let installed: Bool
}

/// What `--model` will accept right now, on this machine.
///
/// Dynamic since v0.3: `vision` is always there, and every manifest model becomes usable
/// the moment `pluck models pull` puts it on disk. The manifest is compiled into the binary
/// as a resource rather than read from the working directory — a manifest the CLI picked up
/// from wherever it happened to run would be a way to point the downloader anywhere.
enum EngineCatalog {
    static let defaultEngineID = "vision"

    static let vision = EngineDescriptor(
        id: "vision",
        summary: "Apple Vision foreground segmentation (macOS 14+)",
        builtIn: true,
        installed: true
    )

    static let registry: ModelRegistry? = {
        guard let url = Bundle.module.url(forResource: "manifest", withExtension: "json"),
              let manifest = try? ModelManifest(contentsOf: url)
        else { return nil }
        return ModelRegistry(manifest: manifest)
    }()

    static var installed: [EngineDescriptor] {
        [vision] + (registry?.installedModels().map { descriptor(for: $0, installed: true) } ?? [])
    }

    /// In the manifest, not on disk.
    static var available: [EngineDescriptor] {
        registry?.availableModels().map { descriptor(for: $0, installed: false) } ?? []
    }

    static var all: [EngineDescriptor] { installed + available }

    static func descriptor(for id: String) -> EngineDescriptor? {
        all.first { $0.id == id }
    }

    private static func descriptor(for model: ModelDescriptor, installed: Bool) -> EngineDescriptor {
        EngineDescriptor(
            id: model.id,
            summary: "\(model.displayName) via Core ML, \(model.inputSide)px (\(model.license))",
            builtIn: false,
            installed: installed
        )
    }

    /// One fallible lookup rather than a nil for "unknown" beside a throw for "absent".
    ///
    /// The caller cannot act on the difference — both are exit 3 with the same advice —
    /// and the split let the plan's `descriptor(for:)` check and this one drift apart. It
    /// also has to stay genuinely reachable: `RunPlan` sees the model installed, but a
    /// `pluck models rm` (or a cache wipe) between the plan and the load leaves the
    /// manifest entry standing with nothing on disk under it.
    static func engine(for id: String) async throws -> any MattingEngine {
        if id == vision.id { return VisionEngine() }
        guard let registry, let url = registry.localURL(for: id) else {
            throw PluckError.modelMissing(id: id)
        }
        return try await CoreMLEngine.load(id: id, modelURL: url)
    }

    static var availabilityMessage: String {
        let ids = installed.map(\.id).joined(separator: ", ")
        return "installed models: \(ids)"
    }
}
