import AppKit
import SwiftUI

/// One panel, reused. Clicking a second thumbnail swaps the content rather than stacking
/// windows — an accessory app that leaves a trail of panels behind has no Dock icon to
/// clean them up from.
///
/// Borderless, because §4.7 rule ④ forbids the system title bar: the filename rides on the
/// image in a glass capsule instead. The frame is resized per item so the picture fills the
/// panel edge to edge rather than sitting in a letterbox.
@MainActor
final class PreviewPanelController {
    /// Long edge ceiling and short edge floor from §4.7. When an image is extreme enough
    /// that both cannot hold, the ceiling wins and the checkerboard takes up the slack.
    static let maxLongEdge: CGFloat = 560
    static let minShortEdge: CGFloat = 320
    private static let cornerRadius: CGFloat = 16
    /// Distance to the shelf, and to the edges of the usable screen.
    private static let gap: CGFloat = 10
    private static let margin: CGFloat = 8

    private var panel: PreviewPanel?
    private var host: NSHostingView<CutoutPreviewView>?

    static func contentSize(for item: RecentItem) -> CGSize {
        let width = CGFloat(max(item.pixelWidth, 1))
        let height = CGFloat(max(item.pixelHeight, 1))
        let aspect = width / height

        var size = aspect >= 1
            ? CGSize(width: maxLongEdge, height: maxLongEdge / aspect)
            : CGSize(width: maxLongEdge * aspect, height: maxLongEdge)

        if size.height < minShortEdge && aspect >= 1 {
            size = CGSize(width: minShortEdge * aspect, height: minShortEdge)
        } else if size.width < minShortEdge {
            size = CGSize(width: minShortEdge, height: minShortEdge / aspect)
        }

        return CGSize(
            width: min(size.width, maxLongEdge).rounded(),
            height: min(size.height, maxLongEdge).rounded()
        )
    }

    /// `shelf` is the frame to stay clear of, or nil when the shelf is closed.
    func show(item: RecentItem, model: AppModel, beside shelf: NSRect?) {
        let size = Self.contentSize(for: item)
        let root = CutoutPreviewView(item: item, model: model, onClose: { [weak self] in self?.close() })

        let panel = self.panel ?? makePanel(root: root, size: size)
        host?.rootView = root
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: panel.frame.size, beside: shelf))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Beside the shelf, not on top of it. Stacking two glass panels reads as clutter even
    /// with the z-order right, and the shelf is where the next thumbnail gets clicked —
    /// covering it costs a click. Top edges align so the pair reads as one composition,
    /// and the gap stays small: "out of the way" must not become "across the screen".
    ///
    /// Centre of the screen when the shelf is closed, which is the only time nothing has
    /// to be avoided.
    private func origin(for size: CGSize, beside shelf: NSRect?) -> NSPoint {
        let screen = shelf.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        return Self.origin(for: size, beside: shelf, in: visible)
    }

    /// Split out from the screen lookup so the geometry — which is where the second-display
    /// and narrow-screen mistakes live — can be tested without a display attached.
    static func origin(for size: CGSize, beside shelf: NSRect?, in visible: NSRect) -> NSPoint {
        guard let shelf else {
            return NSPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.midY - size.height / 2).rounded()
            )
        }

        // Whichever side the shelf leaves more room on. The status item is usually near the
        // right edge, so this is usually the left — but "usually" is not a layout rule.
        let x = (shelf.minX - visible.minX) >= (visible.maxX - shelf.maxX)
            ? shelf.minX - Self.gap - size.width
            : shelf.maxX + Self.gap

        return NSPoint(
            x: clamp(x, size.width, visible.minX, visible.maxX).rounded(),
            y: clamp(shelf.maxY - size.height, size.height, visible.minY, visible.maxY).rounded()
        )
    }

    private static func clamp(_ value: CGFloat, _ extent: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        let m = Self.margin
        return min(max(value, low + m), max(low + m, high - extent - m))
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(root: CutoutPreviewView, size: CGSize) -> PreviewPanel {
        let panel = PreviewPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // `isFloatingPanel` is deliberately never touched: its setter *writes* `level`
        // (false → `.normal`), so a `panel.isFloatingPanel = false` line below this one
        // silently threw the level away — which is how the preview kept coming up under
        // the shelf even after the level was set.
        panel.level = .pluckPreview
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in self?.close() }

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let host = NSHostingView(rootView: root)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container

        self.panel = panel
        self.host = host
        return panel
    }
}

/// Esc reaches the window as `cancelOperation(_:)` once the hosting view declines it;
/// a panel does not close on Esc by itself unless it is a sheet. Borderless windows also
/// refuse key status without the override, and Copy/Save need a key window.
final class PreviewPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Before/after wipe. Two identically-fitted layers stacked, the top one masked to the
/// right of the handle: because the cutout has exactly the source image's dimensions,
/// `scaledToFit` in the same frame puts every pixel of both layers on top of each other,
/// so the mask edge is the only thing the eye tracks.
struct CutoutPreviewView: View {
    let item: RecentItem
    let model: AppModel
    var onClose: () -> Void

    @State private var fraction: CGFloat = 0.5
    @State private var before: NSImage?
    @State private var after: NSImage?
    @State private var hovering = false

    var body: some View {
        comparison
            .overlay(alignment: .topLeading) { titleCapsule.padding(10) }
            .overlay(alignment: .topTrailing) { closeButton.padding(10) }
            .overlay(alignment: .bottom) { toolbar }
            .onHover { on in
                withAnimation(.easeOut(duration: 0.12)) { hovering = on }
            }
            .task(id: item.id) {
                before = NSImage(data: item.originalPNG)
                after = NSImage(data: item.pngData)
                fraction = 0.5
            }
    }

    /// The checkerboard is the backdrop, not a neutral grey plate: transparency is the
    /// product, and §4.7 rule ① rules out letterbox chrome.
    private var comparison: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                Checkerboard()

                layer(before)

                ZStack {
                    Checkerboard()
                    layer(after)
                }
                .mask(alignment: .leading) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: max(0, width * fraction))
                        Rectangle()
                    }
                }

                handle(width: width, height: geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        fraction = min(1, max(0, value.location.x / width))
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func layer(_ image: NSImage?) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleCapsule: some View {
        GlassCapsule {
            Text(item.suggestedName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var closeButton: some View {
        GlassCircleButton(symbol: "xmark", diameter: 24, label: L.s("Close"), action: onClose)
            .opacity(hovering ? 1 : 0)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            GlassCircleButton(symbol: "doc.on.doc", diameter: 34, label: L.s("Copy")) { model.copy(item) }
            GlassCircleButton(symbol: "arrow.down.to.line", diameter: 34, label: L.s("Save")) { model.save(item) }
                .keyboardShortcut("s", modifiers: .command)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func handle(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: height)
                .shadow(color: .black.opacity(0.35), radius: 2)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.45), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
        }
        .position(x: width * fraction, y: height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
