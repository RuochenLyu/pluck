import AppKit
import SwiftUI

/// The menu-bar shelf. A non-activating borderless `NSPanel` rather than an `NSPopover`
/// because the container's corner radius, material and padding are ours to draw
/// (product-plan §4.7) and a popover's frame is not.
///
/// The shelf opens two ways — clicking the status item, and dropping a file on it — and
/// closes on a click anywhere outside (decisions.md 2026-07-27). Dragging *into* the shelf
/// still works but is no longer the load-bearing path, which is what lets the dismissal be
/// this eager: the drag that used to be broken by it now lands on the icon instead.
@MainActor
final class ShelfPanelController {
    private(set) var panel: ShelfPanel?
    private var host: NSHostingView<ShelfView>?

    /// Shared with the hosted `ShelfView` so the coral drop rim stays a SwiftUI concern
    /// while the drag destination itself is AppKit.
    let dropTarget = DropTarget()

    var onDrop: (([DroppedPayload]) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Distance between the menu bar item and the top of the shelf.
    private static let gap: CGFloat = 6
    /// Keep-off margin from the edges of the usable screen.
    private static let margin: CGFloat = 8
    private static let cornerRadius: CGFloat = 16

    func install(content: ShelfView) {
        let size = ShelfView.size
        let panel = ShelfPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .pluckShelf
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.onCancel = { [weak self] in self?.close() }

        // The rounded material container is ours to draw now that there is no window
        // frame: `.popover` material behind the window is what an NSPopover uses, so the
        // shelf keeps the same substance it had before.
        //
        // It is also the drag destination for the whole shelf. AppKit looks for a
        // registered view by hit-testing and then walking *up* the superview chain, so
        // sitting under the hosting view costs nothing — and unlike SwiftUI's `onDrop`
        // it receives the real pasteboard, file URLs and all.
        let backdrop = ShelfBackdropView(frame: NSRect(origin: .zero, size: size))
        backdrop.dropTarget = dropTarget
        backdrop.onDrop = { [weak self] payloads in self?.onDrop?(payloads) }
        backdrop.material = .popover
        backdrop.state = .active
        backdrop.blendingMode = .behindWindow
        backdrop.autoresizingMask = [.width, .height]
        // `.behindWindow` blur is composited by the window server outside the layer tree,
        // so `cornerRadius` + `masksToBounds` does not touch it — the corners stay square
        // and opaque. `maskImage` is the only knob that reaches it.
        backdrop.maskImage = Self.cornerMask(radius: Self.cornerRadius)

        let host = NSHostingView(rootView: content)
        host.frame = backdrop.bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        // The SwiftUI side still needs its own clip: the mask shapes the material, not
        // the views drawn on top of it.
        host.layer?.cornerRadius = Self.cornerRadius
        host.layer?.masksToBounds = true

        backdrop.addSubview(host)
        panel.contentView = backdrop

        self.panel = panel
        self.host = host
    }

    func show(from button: NSStatusBarButton) {
        guard let panel else { return }
        panel.setFrameOrigin(origin(for: button, size: panel.frame.size))
        // Non-activating panels do not take focus by themselves, and ⌘V needs a key
        // window to land in — so opening is the one moment the app asserts itself.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// A rounded rect just big enough to hold two corners, with cap insets so AppKit
    /// stretches the flat middle to whatever size the shelf ends up. Circular corners
    /// rather than `.continuous`: the mask is a drawn path, the SwiftUI rim is a
    /// `RoundedRectangle`, and the two shapes have to agree or the rim gets clipped.
    private static func cornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Centred under the status item, clamped into the visible frame. Without the clamp a
    /// status item near the right edge (or on a display whose menu bar is not at the top
    /// of the global coordinate space) pushes half the shelf off screen.
    private func origin(for button: NSStatusBarButton, size: CGSize) -> NSPoint {
        guard let window = button.window else { return .zero }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchor.midX - size.width / 2
        var y = anchor.minY - Self.gap - size.height

        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let m = Self.margin
            x = min(max(x, visible.minX + m), max(visible.minX + m, visible.maxX - size.width - m))
            y = min(max(y, visible.minY + m), max(visible.minY + m, visible.maxY - size.height - m))
        }
        return NSPoint(x: x.rounded(), y: y.rounded())
    }
}

/// Whether a drag is currently over the shelf. Observable rather than a plain callback so
/// the SwiftUI side can render the rim without the controller reaching into the view.
@MainActor
@Observable
final class DropTarget {
    var isTargeted = false
}

/// The shelf's material container, doubling as its drag destination.
final class ShelfBackdropView: NSVisualEffectView {
    var onDrop: (([DroppedPayload]) -> Void)?
    weak var dropTarget: DropTarget?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let accepted = !DroppedPayload.read(from: sender.draggingPasteboard).isEmpty
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
        let payloads = DroppedPayload.read(from: sender.draggingPasteboard)
        guard !payloads.isEmpty else { return false }
        onDrop?(payloads)
        return true
    }

    private func setTargeted(_ on: Bool) {
        MainActor.assumeIsolated { dropTarget?.isTargeted = on }
    }
}

/// Borderless panels refuse key status by default, and Esc only reaches a window as
/// `cancelOperation(_:)` after the hosted view declines it.
final class ShelfPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
