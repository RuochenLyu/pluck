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
    }

    mutating func toggle(_ id: UUID) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }

    mutating func selectAll<S: Sequence>(_ all: S) where S.Element == UUID {
        ids = Set(all)
    }

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
