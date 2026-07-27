import AppKit
import UniformTypeIdentifiers

/// The status item's button is created by AppKit and cannot be subclassed, so drag
/// support is added by an overlay view that fills it. AppKit finds drag destinations by
/// hit-testing, which means this view also swallows clicks — it forwards them to
/// `onClick` rather than trying to be transparent to the mouse.
final class StatusItemDropView: NSView {
    var onClick: (() -> Void)?
    var onDrop: (([DroppedPayload]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setAccessibilityLabel(L.s("Pluck — drag an image here or click to open"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        highlight(true)
        return payloads(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        highlight(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        highlight(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let items = payloads(from: sender.draggingPasteboard)
        guard !items.isEmpty else { return false }
        onDrop?(items)
        return true
    }

    private func highlight(_ on: Bool) {
        (superview as? NSStatusBarButton)?.highlight(on)
    }

    private func payloads(from pasteboard: NSPasteboard) -> [DroppedPayload] {
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

enum DroppedPayload: Sendable, Equatable {
    case file(URL)
    case data(Data)
}
