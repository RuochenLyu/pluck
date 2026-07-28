import Foundation
import PluckKit

/// The app's one copy of "which engine, and is it ready yet".
///
/// An actor because loading a Core ML model is a 5–10 second compile the first time and
/// must happen exactly once no matter how many images are dropped at the same instant: the
/// second dropper waits on the first one's `Task` rather than starting a second compile of
/// the same 94 MB package.
actor EngineProvider {
    static let shared = EngineProvider()

    /// What the caller got, and what they asked for if those differ. The distinction exists
    /// so the status line can say "your model could not be loaded" once, rather than the
    /// user silently getting Vision's edges and wondering why the hair looks worse.
    struct Resolved {
        let engine: any MattingEngine
        let requested: String
        let fellBackFrom: String?
    }

    private let catalog: EngineCatalog
    private var loaded: [String: any MattingEngine] = [:]
    private var loading: [String: Task<any MattingEngine, any Error>] = [:]

    init(catalog: EngineCatalog = .bundled(in: .main)) {
        self.catalog = catalog
    }

    var installedEngines: [EngineDescriptor] { catalog.installed }

    /// True when using this engine costs nothing but the matting itself.
    func isReady(_ id: String) -> Bool {
        id == EngineCatalog.defaultEngineID || loaded[id] != nil
    }

    /// Never throws. A model that will not load — deleted behind the app's back, corrupt,
    /// or from a manifest this build cannot read — is a reason to fall back to Vision and
    /// say so, not a reason to refuse the user's picture. The engine they picked stays
    /// picked: the next drop tries again, and a model reinstalled in Settings starts
    /// working without anyone touching the preference.
    func resolve(_ id: String) async -> Resolved {
        if id == EngineCatalog.defaultEngineID {
            return Resolved(engine: VisionEngine(), requested: id, fellBackFrom: nil)
        }
        if let engine = loaded[id] {
            return Resolved(engine: engine, requested: id, fellBackFrom: nil)
        }
        do {
            let engine = try await load(id)
            loaded[id] = engine
            return Resolved(engine: engine, requested: id, fellBackFrom: nil)
        } catch {
            return Resolved(engine: VisionEngine(), requested: id, fellBackFrom: id)
        }
    }

    /// Drops a loaded engine, so a model that was deleted and downloaded again is compiled
    /// from the new bytes instead of served from memory.
    func forget(_ id: String) {
        loaded[id] = nil
        loading[id]?.cancel()
        loading[id] = nil
    }

    private func load(_ id: String) async throws -> any MattingEngine {
        if let existing = loading[id] {
            return try await existing.value
        }
        let catalog = catalog
        let task = Task { try await catalog.engine(for: id) }
        loading[id] = task
        defer { loading[id] = nil }
        return try await task.value
    }
}
