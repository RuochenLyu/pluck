import AppKit
import SwiftUI

/// One panel, reused. Clicking a second thumbnail swaps the content rather than stacking
/// windows — an accessory app that leaves a trail of panels behind has no Dock icon to
/// clean them up from.
@MainActor
final class PreviewPanelController {
    static let contentSize = CGSize(width: 480, height: 420)

    private var panel: PreviewPanel?
    private var host: NSHostingController<CutoutPreviewView>?

    func show(item: RecentItem, model: AppModel) {
        let root = CutoutPreviewView(item: item, model: model)
        if let panel, let host {
            host.rootView = root
            panel.title = item.suggestedName
            panel.makeKeyAndOrderFront(nil)
        } else {
            let host = NSHostingController(rootView: root)
            let panel = PreviewPanel(
                contentRect: NSRect(origin: .zero, size: Self.contentSize),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = false
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.contentViewController = host
            panel.title = item.suggestedName
            panel.setContentSize(Self.contentSize)
            panel.center()
            self.panel = panel
            self.host = host
            panel.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }
}

/// Esc reaches the window as `cancelOperation(_:)` once the hosting view declines it;
/// a panel does not close on Esc by itself unless it is a sheet.
private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

/// Before/after wipe. Two identically-fitted layers stacked, the top one masked to the
/// right of the handle: because the cutout has exactly the source image's dimensions,
/// `scaledToFit` in the same frame puts every pixel of both layers on top of each other,
/// so the mask edge is the only thing the eye tracks.
struct CutoutPreviewView: View {
    let item: RecentItem
    let model: AppModel

    @State private var fraction: CGFloat = 0.5
    @State private var before: NSImage?
    @State private var after: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            comparison
            Divider()
            actions
        }
        .task(id: item.id) {
            before = NSImage(data: item.originalPNG)
            after = NSImage(data: item.pngData)
            fraction = 0.5
        }
    }

    private var comparison: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

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

    private func handle(width: CGFloat, height: CGFloat) -> some View {
        let x = width * fraction
        return ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: height)
                .shadow(color: .black.opacity(0.35), radius: 2)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black.opacity(0.7))
                .frame(width: 26, height: 26)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 3)
        }
        .position(x: x, y: height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Text(L.s("Before / after"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button(L.s("Copy")) { model.copy(item) }
            Button(L.s("Save")) { model.save(item) }
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
