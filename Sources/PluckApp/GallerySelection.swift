import Foundation

/// Which cutouts the main window's gallery has picked out, and what a click does to that.
///
/// A type of its own, and pure, because selection is the one part of the gallery that is a
/// *rule* rather than a drawing: a click means one thing, a ⌘-click another, and the export
/// button's label and its file set both read off the result. All of that is wrong in ways a
/// screenshot cannot show — a stale id left behind by a deleted cutout would have Export
/// write four files while the button said five.
struct GallerySelection: Equatable {
    private(set) var ids: Set<UUID> = []

    /// Where a ⇧-click measures from: the last card clicked on its own. Finder's rule.
    private(set) var anchorID: UUID?

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// A plain click. Selecting is exclusive — this is a gallery of pictures, and clicking
    /// one has to mean "that one" — and clicking the single selected card again clears it,
    /// so the gesture that selects is also the gesture that undoes it. Clicking a different
    /// card while several are selected replaces the lot rather than adding to it; ⌘ is how
    /// the user says "as well as".
    mutating func click(_ id: UUID, extending: Bool = false) {
        if extending {
            toggle(id)
        } else if ids == [id] {
            ids = []
        } else {
            ids = [id]
        }
        anchorID = id
    }

    /// ⇧-click: everything between the anchor and here, in the grid's order. The anchor
    /// stays put, so a second ⇧-click re-measures from the same place — Finder's rule, and
    /// the reason this cannot be expressed as repeated `click`s.
    mutating func range(to id: UUID, order: [UUID]) {
        guard let anchorID,
              let a = order.firstIndex(of: anchorID),
              let b = order.firstIndex(of: id)
        else {
            click(id)
            return
        }
        ids = Set(order[min(a, b)...max(a, b)])
    }

    /// Exactly this one, regardless of what was selected — what opening the preview means.
    mutating func select(only id: UUID) {
        ids = [id]
        anchorID = id
    }

    mutating func toggle(_ id: UUID) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }

    mutating func selectAll<S: Sequence>(_ all: S) where S.Element == UUID {
        ids = Set(all)
    }

    /// The whole set at once — what the list view hands back, having run ⌘, ⇧ and the
    /// keyboard itself.
    mutating func replace(_ newIDs: Set<UUID>) {
        ids = newIDs
    }

    var idSet: Set<UUID> { ids }

    mutating func clear() {
        ids = []
    }

    /// Forgets whatever is no longer on screen. Deleting a selected cutout, or clearing the
    /// grid, must not leave the button counting things that do not exist.
    mutating func prune<S: Sequence>(to present: S) where S.Element == UUID {
        ids.formIntersection(Set(present))
    }
}

extension Array where Element == RecentItem {
    /// The entries a selection stands for, in the grid's own order — so an export writes them
    /// in the order the user is looking at rather than in whatever order a `Set` iterates.
    func selected(by selection: GallerySelection) -> [RecentItem] {
        filter { selection.contains($0.id) }
    }
}
