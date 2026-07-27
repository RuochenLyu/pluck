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

    func show(item: RecentItem, model: AppModel) {
        let size = Self.contentSize(for: item)
        let root = CutoutPreviewView(item: item, model: model, onClose: { [weak self] in self?.close() })

        let panel = self.panel ?? makePanel(root: root, size: size)
        host?.rootView = root
        panel.setContentSize(size)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
        panel.level = .pluckPreview
        panel.isFloatingPanel = false
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
