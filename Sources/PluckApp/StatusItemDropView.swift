import AppKit
import UniformTypeIdentifiers

/// The status item's button is created by AppKit and cannot be subclassed, so drag
/// support is added by an overlay view that fills it. AppKit finds drag destinations by
/// hit-testing, which means this view also swallows clicks — it forwards them to
/// `onClick` rather than trying to be transparent to the mouse.
final class StatusItemDropView: NSView {
    var onClick: (() -> Void)?
    /// The right button, which this view has to route explicitly for the same reason it has
    /// to route the left one: hit-testing gives it every mouse event the status item gets,
    /// so an `NSStatusItem.menu` or a `sendAction(on:)` on the button underneath would never
    /// be reached.
    var onSecondaryClick: (() -> Void)?
    var onDrop: (([DroppedPayload]) -> Void)?
    /// The icon is the whole affordance here: there is no window to light up, so the mark
    /// itself has to say "let go and I will catch this".
    var onDragTargeted: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        relabel()
    }

    /// The one string this view keeps rather than asks for, so the language switch has to
    /// come back for it (`AppDelegate`). VoiceOver users are the last people who should be
    /// told to relaunch.
    func relabel() {
        setAccessibilityLabel(L.s("Pluck — drag an image here or click to open"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let accepted = !payloads(from: sender.draggingPasteboard).isEmpty
        setTargeted(accepted)
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setTargeted(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        setTargeted(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setTargeted(false)
        let items = payloads(from: sender.draggingPasteboard)
        guard !items.isEmpty else { return false }
        onDrop?(items)
        return true
    }

    /// Only highlight once the pasteboard is known to hold an image — a highlight under a
    /// dragged .zip would be a promise the drop cannot keep.
    private func setTargeted(_ on: Bool) {
        (superview as? NSStatusBarButton)?.highlight(on)
        onDragTargeted?(on)
    }

    private func payloads(from pasteboard: NSPasteboard) -> [DroppedPayload] {
        DroppedPayload.read(from: pasteboard)
    }
}

enum DroppedPayload: Sendable, Equatable {
    case file(URL)
    case data(Data)

    /// Whether a drag arriving at one of our destinations started somewhere else.
    ///
    /// `NSDraggingInfo.draggingSource` is non-nil exactly when the drag began in this
    /// process, which is how a cutout being dragged *out* of the grid is told apart from a
    /// file being dragged *in*. Without this, hauling a result towards Finder lights up the
    /// window it is leaving and offers to pluck it again — an app answering its own gesture,
    /// and the reason the drop rim would flash for a drag that was never for it.
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
    /// encoding *and* its name, and the name is what the save panel and the preview's
    /// title capsule show. SwiftUI's `onDrop` cannot do this — it hands back a provider
    /// flattened to `public.jpeg` with a nil `suggestedName` — which is why both drop
    /// targets in this app are AppKit views.
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
