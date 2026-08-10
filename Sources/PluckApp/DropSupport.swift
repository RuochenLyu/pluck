import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Whether a drag is currently over the window. Observable rather than a plain callback so
/// the SwiftUI side can render the accent rim without the controller reaching into the view.
@MainActor
@Observable
final class DropTarget {
    var isTargeted = false
}

enum DroppedPayload: Sendable, Equatable {
    case file(URL)
    case data(Data)

    /// Whether a drag arriving at one of our destinations started somewhere else.
    ///
    /// `NSDraggingInfo.draggingSource` is non-nil exactly when the drag began in this
    /// process, which is how a cutout being dragged *out* of the grid is told apart from a
    /// file being dragged *in*. Without this, hauling a result towards Finder lights up the
    /// window it is leaving and offers to pluck it again — an app answering its own gesture.
    ///
    /// Dragging out is unaffected: the destination declining a drag is not the source
    /// withdrawing it, so the pasteboard still reaches whatever the user was aiming at.
    static func isForeignDrag(source: Any?) -> Bool { source == nil }

    /// The bytes exactly as they exist outside this app. `.file` re-reads from disk rather
    /// than handing back something re-encoded, because these bytes get fingerprinted and the
    /// hash only means anything if every path hashes the same thing.
    var bytes: Data? {
        switch self {
        case .file(let url): try? Data(contentsOf: url)
        case .data(let data): data
        }
    }

    /// What the batch list calls this row. A dropped file has a name; a dragged bitmap
    /// never did, and inventing one from its bytes would be worse than saying where it
    /// came from.
    var displayName: String {
        switch self {
        case .file(let url): url.lastPathComponent
        case .data: L.s("Dropped image")
        }
    }

    /// File URLs before bitmap flavors, always: a dragged file carries its original
    /// encoding *and* its name, and the name is what the save panel and the preview show.
    /// SwiftUI's `onDrop` cannot do this — it hands back a provider flattened to
    /// `public.jpeg` with a nil `suggestedName` — which is why the drop target stays AppKit.
    static func read(from pasteboard: NSPasteboard) -> [DroppedPayload] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingContentsConformToTypes: [UTType.image.identifier]]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls.map { .file($0) }
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return [.data(data)]
            }
        }
        return []
    }
}
