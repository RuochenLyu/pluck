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
    private static let cornerRadius: CGFloat = Tokens.panelRadius
    /// Distance to the shelf, and to the edges of the usable screen.
    private static let gap: CGFloat = 10
    private static let margin: CGFloat = 8

    /// The panel decodes at its own size, not the cutout's: 560pt on the long edge at 2×,
    /// which is every pixel a Retina display can show of it. Decoding the export instead
    /// meant holding two full-resolution `NSImage`s — a 24-megapixel pair is ~200 MB — to
    /// draw about a megapixel.
    static let decodeMaxEdge = Int(maxLongEdge) * 2

    private var panel: PreviewPanel?
    private var host: NSHostingView<PreviewRoot>?

    /// Where the panel was last put down by us, and where the user moved it to afterwards.
    /// Dragging a panel somewhere is an explicit answer to "where should this be"; placing
    /// it back beside the shelf on every open overrules that answer every single time, which
    /// is why the position is remembered for the rest of the session once it is given.
    ///
    /// Top-left rather than the AppKit origin: the panel is resized per image, and
    /// `setContentSize` grows it upward from the bottom-left, so a remembered bottom edge
    /// would make the panel jump around as the user clicks through cutouts of different
    /// shapes. The top-left corner is the one the eye is actually tracking.
    private var placedOrigin: NSPoint?

    /// Kept in preferences rather than in this object: where a user put a window is the
    /// kind of thing an app is expected to still know tomorrow, and the clamp on the way
    /// out already handles a screen that has since changed shape.
    private var userTopLeft: NSPoint? {
        get { preferences?.previewTopLeft }
        set { preferences?.previewTopLeft = newValue }
    }

    private let preferences: Preferences?

    init(preferences: Preferences? = nil) {
        self.preferences = preferences
    }

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
        // Before anything moves it.
        rememberIfMoved()
        host?.rootView = PreviewRoot(content: root)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: panel.frame.size, beside: shelf))
        placedOrigin = panel.frame.origin
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
        if let topLeft = userTopLeft {
            let screen = NSScreen.screens.first { $0.frame.contains(topLeft) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                return Self.origin(for: size, keeping: topLeft, in: visible)
            }
        }
        let screen = shelf.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        return Self.origin(for: size, beside: shelf, in: visible)
    }

    /// Hangs the panel from a corner the user chose, clamped like any other placement — a
    /// remembered position must not survive into a screen arrangement where it is off screen.
    static func origin(for size: CGSize, keeping topLeft: NSPoint, in visible: NSRect) -> NSPoint {
        NSPoint(
            x: clamp(topLeft.x, size.width, visible.minX, visible.maxX).rounded(),
            y: clamp(topLeft.y - size.height, size.height, visible.minY, visible.maxY).rounded()
        )
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
        // Sampled here too, not only on the next `show`. Dragging the panel somewhere and
        // then quitting is an ordinary sequence, and it used to throw the answer away.
        rememberIfMoved()
        panel?.orderOut(nil)
        // A hidden panel is not a cheap panel: the two decoded halves are the largest
        // objects the app holds, and they would sit there until the next cutout is opened —
        // or forever, if there is not one. Dropping the root view releases the `@State` they
        // live in.
        host?.rootView = PreviewRoot(content: nil)
    }

    /// The key window question for `AppDelegate`'s ⌘W: this panel is borderless, so the
    /// File ▸ Close menu item cannot reach it.
    func owns(_ window: NSWindow?) -> Bool {
        window != nil && window === panel
    }

    /// A frame that no longer matches where we put it can only have been dragged there.
    private func rememberIfMoved() {
        guard let panel, let moved = Self.movedTopLeft(of: panel.frame, placedAt: placedOrigin) else { return }
        userTopLeft = moved
    }

    /// nil when the panel is still where it was put down. Split out from the panel so the
    /// rule — which corner is remembered, and when — is testable without a window server.
    static func movedTopLeft(of frame: NSRect, placedAt placed: NSPoint?) -> NSPoint? {
        guard let placed, frame.origin != placed else { return nil }
        return NSPoint(x: frame.minX, y: frame.maxY)
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

        // The same backdrop the shelf gets, for the same reason: on macOS 26 the rounded
        // corner is `NSGlassEffectView`'s to own, which also means it survives
        // `setContentSize` — the panel is resized to each cutout's aspect ratio on every
        // open, and a hand-rounded layer had to be told about that. The glass is mostly
        // *behind* opaque content here (the checkerboard is content, §4.7, so it does not
        // become translucent to show it off); what it buys is the lens edge around the
        // picture and a corner that is the system's shape rather than an approximation of it.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let host = NSHostingView(rootView: PreviewRoot(content: root))
        PanelBackdrop.install(content: host, in: container, cornerRadius: Self.cornerRadius)
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

/// The panel's root: a preview, or nothing at all. The empty case is what `close()` swaps
/// in — SwiftUI has no other way to tell a view to let go of what its `@State` is holding,
/// and there is no "the panel is hidden" signal inside the view to hang it on.
struct PreviewRoot: View {
    var content: CutoutPreviewView?

    var body: some View {
        ZStack {
            if let content { content }
        }
    }
}

/// What the engine switcher's contents depend on. Two values, because it goes stale for two
/// different reasons: the panel being pointed at a different cutout, and a re-pluck landing
/// in the grid while this one is open.
private struct EngineMenuKey: Equatable {
    let item: UUID
    let cutouts: Int
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
    @State private var pointerInside = false
    @State private var options: [AppModel.EngineOption] = []

    var body: some View {
        comparison
            .overlay(alignment: .top) { dragBand }
            .overlay(alignment: .bottomLeading) { sideLabel(L.s("Original"), visible: Self.labels(at: fraction).original) }
            .overlay(alignment: .bottomTrailing) {
                sideLabel(L.s("Cutout"), visible: Self.labels(at: fraction).cutout)
            }
            .overlay(alignment: .topTrailing) { closeButton.padding(8) }
            .overlay(alignment: .bottom) { toolbar }
            .onHover { on in pointerInside = on }
            // Re-read when the grid changes, not only when the panel swaps item: a finished
            // download changes what an entry costs, and a re-pluck landing changes which
            // engine is ticked.
            .task(id: EngineMenuKey(item: item.id, cutouts: model.recents.items.count)) {
                options = await model.engineOptions(for: item)
            }
            .task(id: item.id) {
                fraction = 0.5
                // Both halves are files now, and `Data(contentsOf:)` blocks. Reading them
                // on the main actor would stall the click that opened the panel for as
                // long as the disk takes; the images arrive a frame later instead.
                //
                // The "before" half was downsampled on the way to disk (`previewMaxEdge`).
                // The "after" half is the export, at whatever the camera shot — so it is
                // fitted to the panel here, on this same detached hop.
                let item = item
                let maxEdge = PreviewPanelController.decodeMaxEdge
                let bytes = await Task.detached(priority: .userInitiated) {
                    (item.originalPNG(), PluckService.fitted(item.pngData(), maxEdge: maxEdge))
                }.value
                before = bytes.0.flatMap(NSImage.init(data:))
                after = bytes.1.flatMap(NSImage.init(data:))
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

    /// The strip the title rides on is the title bar, so it drags the window — that is the
    /// habit §4.7 rule ④ has to pay for when it takes the system one away. It sits above
    /// the wipe gesture, which gives up its top 44pt; below that the whole image still
    /// scrubs, which is the interaction worth protecting.
    private var dragBand: some View {
        HStack(spacing: 0) {
            WindowDragHandle()
            // Stops short of the close button. Overlapping a control with a drag region is
            // a hit-testing coin flip, and the losing side is a button that does nothing.
            Spacer(minLength: 0).frame(width: 44)
        }
        .frame(height: 44)
    }

    /// Which half is which, said once on each half instead of by a floating pill that named
    /// the file and left "which side am I looking at" to be inferred from the wipe.
    ///
    /// A label goes away when the handle is about to run it over: the alternative is a
    /// caption sitting on top of the seam it is describing.
    static func labels(at fraction: CGFloat) -> (original: Bool, cutout: Bool) {
        let clearance: CGFloat = 0.18
        return (original: fraction > clearance, cutout: fraction < 1 - clearance)
    }

    /// One capsule per half, and nothing more: "which of the two cutouts of this photo am I
    /// looking at" is answered by the switcher in the toolbar, which names the engine as part
    /// of being the way to change it. Saying it twice made the corner capsule a second,
    /// quieter label for the same fact.
    private func sideLabel(_ text: String, visible: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // Same substance as the toolbar capsule it shares the picture with, one grade
            // lighter below 26 — these two words are a caption, not a control, and the
            // heaviest material available would make them the loudest thing on the photo.
            .pluckGlass(in: Capsule(), fallback: .thinMaterial)
            .padding(8)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: visible)
            .allowsHitTesting(false)
    }

    /// Always drawn, never revealed on hover. A borderless window has no other visible way
    /// out — Esc works but nothing on screen says so, and a control that appears only once
    /// the pointer is already in the right place cannot teach anyone where that is.
    private var closeButton: some View {
        GlassCircleButton(symbol: "xmark", diameter: 28, label: L.s("Close"), action: onClose)
    }

    /// A capsule that floats over the picture, not a band that cuts a strip off the bottom
    /// of it: the panel is sized to the cutout's aspect ratio, and a full-width bar means
    /// every preview is drawn with a grey ribbon across the part of the image nearest the
    /// pointer.
    ///
    /// Shown while the pointer is in the panel. It stays in the hierarchy at zero opacity
    /// rather than being removed, so ⌘S keeps working with the mouse elsewhere.
    private var toolbar: some View {
        HStack(spacing: 4) {
            PlainIconButton(symbol: "doc.on.doc", size: 16, side: Tokens.toolbarControlSide, label: L.s("Copy")) { model.copy(item) }
            PlainIconButton(symbol: "arrow.down.to.line", size: 16, side: Tokens.toolbarControlSide, label: L.s("Save")) { model.save(item) }
                .keyboardShortcut("s", modifiers: .command)
            if model.isRepluckRunning(item) {
                // The same spinner the grid's placeholder cell is showing for this job, in
                // the surface the user asked from. Nothing more: the placeholder carries the
                // picture, and the status line carries a download if there is one.
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Tokens.toolbarControlSide, height: Tokens.toolbarControlSide)
            } else if !options.isEmpty {
                engineSwitcher
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        // One lens holding three controls, not three lenses in a row. `.buttonStyle(.glass)`
        // on each of them would stack glass on glass — the capsule is already the glass, and
        // the buttons inside it are glyphs with a hover highlight, which is how macOS 26
        // draws its own toolbars. Below 26 it is the heaviest material available: this
        // capsule floats over the user's photograph, the one surface in the app with no idea
        // what is behind it, and a light material there needs a white hairline to survive.
        .pluckGlass(in: Capsule())
        .pluckShadow(isLiquid ? Tokens.glassShadow : Tokens.controlShadow)
        .padding(.bottom, 12)
        .opacity(pointerInside ? 1 : 0)
        .allowsHitTesting(pointerInside)
        .animation(.easeOut(duration: 0.15), value: pointerInside)
    }

    /// Which engine this picture is being looked at through — a standing switch, not a verb.
    ///
    /// It was a circular-arrow button opening a list of engines this photo had not been
    /// through yet, and both halves of that were wrong. A refresh glyph says "do it again",
    /// not "with what"; and a menu that drops an entry each time it is used has no stable
    /// shape to learn, while saying nothing about what is currently on screen. A word plus a
    /// chevron is both facts in one control: the name is the state, the chevron is the door.
    ///
    /// Switching to an engine this picture has already been through costs nothing — the
    /// panel just points at the cutout that exists (`AppModel.showEngine`).
    private var engineSwitcher: some View {
        Menu {
            ForEach(options) { option in
                // A `Toggle` rather than a `Button`, because AppKit draws a checked menu item
                // for it: the tick is how a menu says "this one", and a list of plain buttons
                // would leave the current engine indistinguishable from the alternatives.
                Toggle(isOn: Binding(
                    get: { option.isCurrent },
                    set: { _ in model.showEngine(option.id, for: item) }
                )) {
                    Text(option.menuTitle)
                }
            }
        } label: {
            engineSwitcherLabel
        }
        .modifier(EngineSwitcherChrome())
        .accessibilityLabel(L.s("Engine"))
        .help(L.s("Which engine made this cutout"))
    }

    /// It is the only control in the row that is not a glyph, so it needs a body of its own:
    /// a bare word beside two round buttons reads as a caption rather than as something to
    /// press. What draws that body differs by system — see `EngineSwitcherChrome` — so the
    /// label only draws what the chrome does not already provide.
    @ViewBuilder private var engineSwitcherLabel: some View {
        if #available(macOS 26.0, *) {
            Text(currentEngineLabel)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: Self.engineLabelMaxWidth)
                .frame(height: Tokens.toolbarControlSide - 10)
        } else {
            HStack(spacing: 3) {
                Text(currentEngineLabel)
                    .lineLimit(1)
                    .frame(maxWidth: Self.engineLabelMaxWidth)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: Tokens.toolbarControlSide)
            .background(.quaternary, in: Capsule())
            .contentShape(Capsule())
        }
    }

    /// The toolbar capsule floats over a panel that can be as narrow as 320pt, and the
    /// switcher's title is whatever the manifest calls a model — a string this app does not
    /// author and cannot bound. `.fixedSize()` on the menu means the label's ideal width is
    /// the capsule's width, so without a ceiling here one long model name pushes the capsule
    /// wider than the picture it is floating on.
    private static let engineLabelMaxWidth: CGFloat = 150

    /// The options list is the better source while it has loaded — it carries the manifest's
    /// display name for a model this build has no copy written for — but the label must be
    /// right on the first frame too.
    private var currentEngineLabel: String {
        options.first { $0.isCurrent }?.label ?? EngineLabels.name(item.engineID)
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
                // Not `.interactive()`: the handle is dragged by the whole picture behind it
                // rather than pressed, so it never sees a mouse-down of its own to react to.
                .pluckGlass(in: Circle())
                .pluckShadow(isLiquid ? Tokens.glassShadow : Tokens.controlShadow)
        }
        .position(x: width * fraction, y: height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The engine switcher's body, per system.
///
/// macOS 26 gets `.menuStyle(.button)` + `.buttonStyle(.glass)`: a real glass capsule with the
/// system's own disclosure chevron, which is what a pop-up looks like on 26 and puts the chip
/// in the same substance as the two glyph buttons beside it. Nested inside the toolbar's own
/// lens on purpose — a control *in* a bar is how the system stacks glass, and it is the only
/// thing in that bar with a boundary of its own to draw.
///
/// It cannot simply be `.borderlessButton` plus a hand-drawn chevron on both, which is what
/// this was: on 26 that style stops honouring `.menuIndicator(.hidden)` and drops the label's
/// own background, so the chip rendered as a bare caption with a stray chevron in front of it.
private struct EngineSwitcherChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .fixedSize()
        } else {
            content
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }
}
