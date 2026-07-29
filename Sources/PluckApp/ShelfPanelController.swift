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
    private static let cornerRadius: CGFloat = Tokens.panelRadius

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
        // The system's window shadow, not a drawn one. v2 asks for a deeper, softer drop
        // (roughly 32–40 blur at 22–28%) and that is already what AppKit gives a floating
        // panel at this level; drawing our own would mean an oversized transparent window
        // with the shadow painted inside it, which breaks the drag destination's bounds and
        // buys a shadow the user cannot tell apart from the system's.
        panel.hasShadow = true
        panel.level = .pluckShelf
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.onCancel = { [weak self] in self?.close() }

        // The rounded, blurred container is ours to draw now that there is no window frame —
        // real Liquid Glass on macOS 26, `.hudWindow` below it (`PanelBackdrop`, which is
        // where the reasoning for both lives).
        //
        // This view is no longer the blurred thing itself, only the drag destination and the
        // box the backdrop is installed into. That split is what let the backdrop change
        // substance without the drop path noticing: AppKit finds a registered destination by
        // hit-testing and then walking *up* the superview chain, so it reaches this view
        // whether the glass above it is an `NSGlassEffectView` or an `NSVisualEffectView` —
        // and unlike SwiftUI's `onDrop` it receives the real pasteboard, file URLs and all.
        let backdrop = ShelfBackdropView(frame: NSRect(origin: .zero, size: size))
        backdrop.dropTarget = dropTarget
        backdrop.onDrop = { [weak self] payloads in self?.onDrop?(payloads) }
        backdrop.autoresizingMask = [.width, .height]

        let host = NSHostingView(rootView: content)
        PanelBackdrop.install(content: host, in: backdrop, cornerRadius: Self.cornerRadius)
        panel.contentView = backdrop

        self.panel = panel
        self.host = host
    }

    /// `anchor` is the status item's rect in screen coordinates, or nil when there is no
    /// reachable icon to hang from.
    func show(anchor: NSRect?, on screen: NSScreen?) {
        guard let panel else { return }
        let size = panel.frame.size
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrameOrigin(Self.origin(for: size, under: anchor, in: visible))
        // Non-activating panels do not take focus by themselves, and ⌘V needs a key
        // window to land in — so opening is the one moment the app asserts itself.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Centred under the status item, clamped into the visible frame. Without the clamp a
    /// status item near the right edge (or on a display whose menu bar is not at the top of
    /// the global coordinate space) pushes half the shelf off screen.
    ///
    /// A nil anchor means the icon could not be reached at all — a full menu bar, a notch,
    /// or a third-party manager has swallowed it. The shelf then hangs from the top centre
    /// of the usable area, which is the one place on screen that is never covered by
    /// whatever hid the icon.
    ///
    /// Static and pure so the cases worth testing are the ones this machine does not have.
    static func origin(for size: CGSize, under anchor: NSRect?, in visible: NSRect) -> NSPoint {
        var x: CGFloat
        var y: CGFloat
        if let anchor {
            x = anchor.midX - size.width / 2
            y = anchor.minY - gap - size.height
        } else {
            // `margin`, not `gap`: there is no icon to hang under, and `visible.maxY` is
            // already below the menu bar — so this is an edge keep-off like any other.
            x = visible.midX - size.width / 2
            y = visible.maxY - margin - size.height
        }
        let m = margin
        x = min(max(x, visible.minX + m), max(visible.minX + m, visible.maxX - size.width - m))
        y = min(max(y, visible.minY + m), max(visible.minY + m, visible.maxY - size.height - m))
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

/// The shelf's drag destination, and the box its glass backdrop is installed into.
///
/// A plain `NSView`: what the shelf is *made of* is `PanelBackdrop`'s decision and changes
/// with the OS, while what it *accepts* does not.
final class ShelfBackdropView: NSView {
    var onDrop: (([DroppedPayload]) -> Void)?
    weak var dropTarget: DropTarget?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // A cutout being dragged out of this very grid is not an image being dragged into
        // it (`DroppedPayload.isForeignDrag`).
        guard DroppedPayload.isForeignDrag(source: sender.draggingSource) else { return [] }
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
        guard DroppedPayload.isForeignDrag(source: sender.draggingSource) else { return false }
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
