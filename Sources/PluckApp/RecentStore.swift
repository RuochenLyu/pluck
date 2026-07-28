import Foundation
import Observation
import UniformTypeIdentifiers

/// One finished cutout, as a pointer to the three files `CutoutArchive` wrote for it.
///
/// Only `thumbnailPNG` is resident: the grid draws it constantly and it is ~50 KB. The
/// export and the preview's "before" half are read back on demand — they are megabytes
/// each, and a history of twenty of them in memory would be the largest thing about this
/// app by an order of magnitude.
struct RecentItem: Identifiable, Equatable, Sendable {
    let id: UUID
    /// SHA-256 of the cutout bytes. Identity for de-duplication is the result, not the
    /// source path, so the same picture arriving by drag and by paste is one entry.
    let fingerprint: String
    let thumbnailPNG: Data
    /// The cutout, named after the picture — this is both the export and the file
    /// `NSItemProvider` hands to whatever the cell is dragged into.
    let fileURL: URL
    /// The downsampled input: the "before" half of the preview slider.
    let originalURL: URL
    let suggestedName: String
    /// Pixel size of the cutout. Carried on the item because the preview panel sizes its
    /// window to the aspect ratio *before* it has decoded anything (§4.7).
    let pixelWidth: Int
    let pixelHeight: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        fingerprint: String,
        thumbnailPNG: Data,
        fileURL: URL,
        originalURL: URL,
        suggestedName: String,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.thumbnailPNG = thumbnailPNG
        self.fileURL = fileURL
        self.originalURL = originalURL
        self.suggestedName = suggestedName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
    }

    /// nil when the file is gone — an external delete, or a write that failed at the time.
    /// Callers turn that into the same failure flash any other export error gets, rather
    /// than copying zero bytes and calling it a success.
    func pngData() -> Data? { try? Data(contentsOf: fileURL) }

    func originalPNG() -> Data? { try? Data(contentsOf: originalURL) }

    /// The payload for dragging a cutout out of the grid, carried as bytes rather than as a
    /// promise to read `fileURL` later.
    ///
    /// `NSItemProvider(contentsOf:)` only opens the file when the drag *lands*, which can be
    /// seconds later — and by then Clear, or an eviction off the end of the list, may have
    /// deleted it (`AppModel.discard` removes the directory on a detached task the moment
    /// the entry leaves the store). The drop then silently produces nothing, which is the
    /// one failure mode with no error path at all: the receiving app is not ours to report
    /// in.
    ///
    /// The cost is one synchronous read at the start of the gesture, on a file the user has
    /// just put the pointer on. Paid deliberately: the alternative is a drag whose outcome
    /// depends on what else the grid happened to do while the mouse was moving.
    func dragProvider() -> NSItemProvider {
        guard let data = pngData() else { return NSItemProvider() }
        let provider = NSItemProvider()
        // What the file is called wherever it lands — the whole reason a dropped *file*
        // beats a dropped bitmap.
        provider.suggestedName = suggestedName + ".png"
        provider.registerDataRepresentation(for: .png, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}

/// What `insert` actually did. `promoted` exists because silent de-duplication reads as
/// "nothing happened" to the user (decisions.md 2026-07-27): the caller needs the id so it
/// can flash the row that already held the result. `evicted` exists because the entries
/// pushed off the end own files, and nobody else knows they are gone.
struct InsertResult: Equatable, Sendable {
    var promoted: UUID?
    var evicted: [RecentItem] = []
}

/// Recent cutouts, newest first, capped. Whether any of this survives a quit is the
/// archive's business, not this type's: the store is the order and the cap, and it hands
/// every mutation to a sink so persistence is one line at the call site instead of a
/// concern threaded through the list logic.
@MainActor
@Observable
final class RecentStore {
    /// Twenty, of which the first twelve fill the shelf's four visible rows and the rest
    /// scroll. Matches the persisted history size — a cap that differs from what survives
    /// a restart would mean the grid silently shrinks on relaunch.
    static let defaultCapacity = 20

    private(set) var items: [RecentItem] = []

    private let capacity: Int
    /// Called after every change to `items`. The archive writes its index here; tests
    /// leave it nil.
    var onChange: (@MainActor ([RecentItem]) -> Void)?

    init(capacity: Int = RecentStore.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// Seeds the grid from a previous run. Not `insert` in a loop: these are already in
    /// order, already de-duplicated, and re-inserting them would rewrite the index for
    /// each one before the app has drawn a single frame.
    func restore(_ restored: [RecentItem]) {
        items = Array(restored.prefix(capacity))
    }

    /// Re-plucking the same picture promotes the existing entry instead of filling
    /// the grid with copies.
    @discardableResult
    func insert(_ item: RecentItem) -> InsertResult {
        if let existing = promote(fingerprint: item.fingerprint) {
            return InsertResult(promoted: existing)
        }
        items.insert(item, at: 0)
        var evicted: [RecentItem] = []
        if items.count > capacity {
            evicted = Array(items.suffix(items.count - capacity))
            items.removeLast(items.count - capacity)
        }
        onChange?(items)
        return InsertResult(evicted: evicted)
    }

    /// Moves a matching entry to the front, or nil if there is none. Split out of `insert`
    /// because the other caller recognises the bytes *before* doing the work: a cutout being
    /// plucked a second time is already in the grid, and the fingerprint says so without a
    /// second pass through the engine.
    @discardableResult
    func promote(fingerprint: String) -> UUID? {
        guard let index = items.firstIndex(where: { $0.fingerprint == fingerprint }) else { return nil }
        let promoted = items.remove(at: index)
        items.insert(promoted, at: 0)
        onChange?(items)
        return promoted.id
    }

    /// Returns the entries that were cleared so the caller can delete their files too —
    /// "photos never leave this Mac" also means they do not sit on it after the user has
    /// asked for them to be gone.
    @discardableResult
    func clear() -> [RecentItem] {
        let cleared = items
        items.removeAll()
        onChange?(items)
        return cleared
    }
}
