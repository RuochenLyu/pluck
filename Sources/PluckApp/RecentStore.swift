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
    let createdAt: Date

    init(
        id: UUID = UUID(),
        fingerprint: String,
        pngData: Data,
        thumbnailPNG: Data,
        originalPNG: Data,
        fileURL: URL,
        suggestedName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.pngData = pngData
        self.thumbnailPNG = thumbnailPNG
        self.originalPNG = originalPNG
        self.fileURL = fileURL
        self.suggestedName = suggestedName
        self.createdAt = createdAt
    }
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
    func insert(_ item: RecentItem) {
        if let existing = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            let promoted = items.remove(at: existing)
            items.insert(promoted, at: 0)
            return
        }
        items.insert(item, at: 0)
        if items.count > capacity {
            items.removeLast(items.count - capacity)
        }
    }

    func clear() {
        items.removeAll()
    }
}
