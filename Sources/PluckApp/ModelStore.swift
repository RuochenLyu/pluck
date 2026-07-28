import Foundation
import Observation
import PluckKit

/// One manifest model as the Settings pane needs to see it.
struct ModelRow: Identifiable, Equatable {
    /// Three states, because there are three things the user can do: get it, stop getting
    /// it, or get rid of it. Anything finer (verifying, unpacking) is a phase of
    /// "downloading" that lasts under a second on a local file and would only make the row
    /// flicker.
    enum State: Equatable {
        case available
        /// Nil fraction while the size is unknown, which on a manifest with `bytes` never
        /// actually happens — but a progress bar that invents a number is worse than one
        /// that admits it is waiting.
        case downloading(fraction: Double?)
        case installed
        /// The last attempt failed, and the reason is the user's to read. Still offers
        /// Download: the usual cause is the network, and the usual fix is trying again.
        case failed(String)
    }

    let descriptor: ModelDescriptor
    var state: State

    var id: String { descriptor.id }
    var isInstalled: Bool { state == .installed }
}

/// The Settings pane's model list, and the only place in the app that downloads anything.
///
/// Every action here goes through `ModelRegistry` — the same code path `pluck models pull`
/// uses, including resuming an interrupted download. An app-side downloader would be a
/// second implementation of the one operation in Pluck that touches the network, and so a
/// second place for the digest check to be got wrong.
@MainActor
@Observable
final class ModelStore {
    private(set) var rows: [ModelRow] = []

    /// Nil when this build has no manifest to offer — a dev shell run straight from
    /// `swift run`, where nothing has signed for one (`Scripts/bundle.sh` copies the
    /// manifest into the bundle it signs). The pane says so rather than showing an empty
    /// list that looks like a download failure.
    let registry: ModelRegistry?

    private var tasks: [String: Task<Void, Never>] = [:]
    private let engines: EngineProvider

    init(registry: ModelRegistry?, engines: EngineProvider = .shared) {
        self.registry = registry
        self.engines = engines
        reload()
    }

    convenience init(catalog: EngineCatalog = .bundled(in: .main), engines: EngineProvider = .shared) {
        self.init(registry: catalog.registry, engines: engines)
    }

    func reload() {
        guard let registry else {
            rows = []
            return
        }
        rows = registry.manifest.models.map { descriptor in
            // A download in flight survives a reload: the disk cannot answer "is this being
            // fetched right now", and dropping the row back to `available` mid-transfer
            // would offer a second Download button for the download already running.
            if let existing = rows.first(where: { $0.id == descriptor.id }),
               case .downloading = existing.state {
                return existing
            }
            return ModelRow(
                descriptor: descriptor,
                state: registry.isInstalled(descriptor.id) ? .installed : .available
            )
        }
    }

    var installedIDs: [String] { rows.filter(\.isInstalled).map(\.id) }

    func download(_ id: String) {
        guard let registry, tasks[id] == nil else { return }
        setState(.downloading(fraction: nil), for: id)
        // Hoisted out of the progress closure: a `[weak self]` binding is implicitly
        // mutable, and Swift 6 will not let the `Task` nested inside a concurrent closure
        // capture it. One `let` closure that already holds the weak reference can be.
        let apply: @Sendable @MainActor (ModelRow.State) -> Void = { [weak self] state in
            self?.setState(state, for: id)
        }
        tasks[id] = Task { [weak self] in
            let outcome: Result<Void, any Error>
            do {
                try await registry.install(id) { progress in
                    guard progress.phase == .downloading else { return }
                    let fraction = progress.fraction
                    Task { @MainActor in apply(.downloading(fraction: fraction)) }
                }
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            let cancelled = Task.isCancelled
            await self?.settle(id, outcome: outcome, cancelled: cancelled)
        }
    }

    private func settle(_ id: String, outcome: Result<Void, any Error>, cancelled: Bool) async {
        tasks[id] = nil
        // A model that was deleted and fetched again must be compiled from the new bytes,
        // not served from the copy this process loaded an hour ago.
        await engines.forget(id)
        switch outcome {
        case .success:
            setState(.installed, for: id)
        case .failure where cancelled:
            // The user pressed Cancel. The partial file stays on disk, so pressing Download
            // again continues rather than restarts.
            setState(.available, for: id)
        case .failure(let error):
            setState(.failed(PluckFailure(error).message), for: id)
        }
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
    }

    /// Deletes the model outright rather than moving it to the Trash.
    ///
    /// The Trash is for things the user made and might want back; this is a cache of bytes
    /// that can be fetched again from a URL the app already knows, and it is 94 MB. Leaving
    /// it in the Trash would mean "freed 94 MB" quietly meaning "moved 94 MB", which is the
    /// kind of half-truth a privacy-first app cannot afford to tell about disk either.
    /// Cutouts, which *are* the user's work, are the opposite case and get a confirmation.
    func delete(_ id: String, preferences: Preferences? = nil) {
        guard let registry else { return }
        cancel(id)
        _ = try? registry.remove(id)
        setState(.available, for: id)
        Task { await engines.forget(id) }
        // An engine preference pointing at a model the user just deleted would resolve to
        // Vision on every drop with a warning each time. They removed it on purpose; the
        // picker should say so.
        if preferences?.engineID == id {
            preferences?.engineID = EngineCatalog.defaultEngineID
        }
    }

    private func setState(_ state: ModelRow.State, for id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].state = state
    }
}
