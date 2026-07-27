import Foundation
import Observation

/// One finished cutout. Pure data so the store stays testable without AppKit:
/// `pngData` is the export, `thumbnailPNG` is what the grid decodes, `originalPNG` is the
/// downsampled input the preview slider wipes between, `fileURL` is the on-disk copy
/// handed to `NSItemProvider` when the user drags a cell out.
struct RecentItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let fingerprint: String
    let pngData: Data
    let thumbnailPNG: Data
    let originalPNG: Data
    let fileURL: URL
    let suggestedName: String
    /// Pixel size of the cutout. Carried on the item because the preview panel sizes its
    /// window to the aspect ratio *before* it has decoded anything (§4.7).
    let pixelWidth: Int
    let pixelHeight: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        fingerprint: String,
        pngData: Data,
        thumbnailPNG: Data,
        originalPNG: Data,
        fileURL: URL,
        suggestedName: String,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.pngData = pngData
        self.thumbnailPNG = thumbnailPNG
        self.originalPNG = originalPNG
        self.fileURL = fileURL
        self.suggestedName = suggestedName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
    }
}

/// What `insert` actually did. `promoted` exists because silent de-duplication reads as
/// "nothing happened" to the user (decisions.md 2026-07-27): the caller needs the id so it
/// can flash the row that already held the result.
enum InsertResult: Equatable, Sendable {
    case inserted
    case promoted(UUID)
}

/// Session-only history: memory, newest first, capped. Nothing is persisted —
/// "photos never leave this Mac" also means they do not quietly accumulate on it.
@MainActor
@Observable
final class RecentStore {
    /// Twelve = four full rows of the 3-column grid, which is what the compact drop strip
    /// leaves room for.
    static let defaultCapacity = 12

    private(set) var items: [RecentItem] = []

    private let capacity: Int

    init(capacity: Int = RecentStore.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// Re-plucking the same picture promotes the existing entry instead of filling
    /// the grid with copies; identity is the cutout bytes, not the source path.
    @discardableResult
    func insert(_ item: RecentItem) -> InsertResult {
        if let existing = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            let promoted = items.remove(at: existing)
            items.insert(promoted, at: 0)
            return .promoted(promoted.id)
        }
        items.insert(item, at: 0)
        if items.count > capacity {
            items.removeLast(items.count - capacity)
        }
        return .inserted
    }

    /// Returns the files that backed the cleared entries so the caller can delete the
    /// temporary copies too — "photos never leave this Mac" also means they do not sit in
    /// `/tmp` after the user has asked for them to be gone.
    @discardableResult
    func clear() -> [URL] {
        let urls = items.map(\.fileURL)
        items.removeAll()
        return urls
    }
}
