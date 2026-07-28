import AppKit
import SwiftUI

/// The batch surface: a real, resizable window — on the same glass as everything else.
///
/// §4.7 used to grade the glass by surface and gave this window "标准窗口材质保可读性", on
/// the theory that a window with an arbitrary *other window* behind it cannot afford to be
/// transparent. That entry is withdrawn (decisions.md 2026-07-28). Liquid Glass is not a
/// hole in the window: it tints, refracts and lights its own edge, and the deep-tinted
/// result in `p4-floating.png` is *more* readable than a system-grey fill, not less —
/// readability is what the tint is for. What is left of the standard window is the part
/// that carries meaning: the traffic lights and the resize edges, which are how a window
/// the user can leave open behind other work is operated. They now float on the glass,
/// with no title bar under them and no "Pluck" written across it — the menu bar has
/// already said whose window this is.
@MainActor
final class MainWindowController {
    private var window: NSWindow?

    var onDrop: (([DroppedPayload]) -> Void)?

    private let dropTarget = DropTarget()

    func show(model: AppModel) {
        if window == nil {
            window = make(model: model)
            window?.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// ⌘V is dispatched by `AppDelegate`'s key monitor rather than by a menu item — pasting
    /// into Pluck is not the `paste:` any view here would answer — so the monitor needs to
    /// know whether the event landed in this window. (⌘W is the File ▸ Close item's job:
    /// this is a standard closable window, unlike the shelf and preview panels.)
    func owns(_ window: NSWindow?) -> Bool {
        window != nil && window === self.window
    }

    /// The title is invisible on the window itself but not everywhere — Mission Control, the
    /// Window menu and VoiceOver all read it, and none of them is going to re-ask.
    func languageDidChange() {
        window?.title = L.s("Pluck")
    }

    private func make(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Still set, and still through the catalog: the title is what the window is called
        // in Mission Control, in the Window menu and to VoiceOver. It is only the *drawn*
        // one that goes — a chrome-free glass surface with one word floating at the top of
        // it is a title bar that forgot to draw its own background.
        window.title = L.s("Pluck")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Both, or there is no glass: an opaque window paints its `backgroundColor` under
        // the content view, and `.behindWindow` blending has nothing to reach through.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 400)
        window.tabbingMode = .disallowed

        // The drop destination is the window's own content view rather than a SwiftUI
        // `.onDrop`: SwiftUI hands back a provider flattened to `public.jpeg` with a nil
        // `suggestedName`, and the filename is the one thing a batch list is made of.
        //
        // Same three-layer stack as the shelf, and for the same reason (`ShelfBackdropView`):
        // this view stays a plain `NSView` that only knows about dragging, the glass is
        // installed into it by `PanelBackdrop`, and AppKit still finds the destination by
        // walking up the superview chain from whatever it hit.
        let backdrop = MainWindowContentView()
        backdrop.dropTarget = dropTarget
        backdrop.onDrop = { [weak self] payloads in self?.onDrop?(payloads) }

        let hosting = NSHostingView(rootView: MainWindowView(model: model, dropTarget: dropTarget))
        PanelBackdrop.install(content: hosting, in: backdrop, cornerRadius: 0)
        window.contentView = backdrop
        return window
    }
}

/// Same job as `ShelfBackdropView`, and now made of the same nothing: the drag destination
/// and the box the glass is installed into, and no opinion about which of the two backdrops
/// the running system will put there.
final class MainWindowContentView: NSView {
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

/// The batch surface, as a gallery.
///
/// It was a list of filenames with 44pt thumbnails beside them, under a standing dashed
/// "drop images here" strip. Both were answering questions the user does not have. What is in
/// this window is *pictures* — the one thing a cutout has to be judged on is what it looks
/// like at the edges — and a row of text with a stamp-sized picture at the end of it puts the
/// evidence last. The strip was teaching the drop gesture to someone who had, by definition,
/// already performed it: the window itself is the target, it lights up under a drag, and the
/// empty state still says the whole sentence for anyone who has not.
///
/// So: the shelf's card, at gallery scale, in an adaptive grid. The two surfaces now show the
/// same object drawn the same way, which is what makes them one app rather than two lists of
/// the same files.
struct MainWindowView: View {
    let model: AppModel
    let dropTarget: DropTarget

    /// ~132–150pt, adaptive: the column count is the window's to decide, because this window
    /// is resizable and a fixed count would either strand a 1200pt window with four huge cards
    /// or crush a 480pt one.
    private static let columns = [GridItem(.adaptive(minimum: 132, maximum: 150), spacing: 12)]
    private static let cellHeight: CGFloat = 132

    /// Room for the traffic lights, which now stand on the glass with no title bar under
    /// them. Nothing scrolls beneath them on purpose: a card sliding under three buttons
    /// that have no material of their own to separate them is the cost of the missing bar,
    /// and 28pt of quiet glass is the price of not paying it.
    private static let titleBarInset: CGFloat = 28

    /// One list, newest first — the same order and the same identities as the shelf grid.
    /// The p2 mockup queues oldest-first, which reads well for exactly one drop and stops
    /// meaning anything the moment restored history shares the list: "first" would then be
    /// a cutout from last week.
    private var cells: [GalleryCell] {
        model.pendingItems.map(GalleryCell.pending) + model.recents.items.map(GalleryCell.done)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let batch = model.batch, batch.total > 1, !model.pendingItems.isEmpty {
                progress(batch)
            }
            if cells.isEmpty {
                dropZone
            } else {
                grid
            }
            bottomBar
        }
        .padding(.top, Self.titleBarInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: dropTarget.isTargeted)
    }

    /// The whole window is the drop target, so the whole window is what answers a drag: one
    /// accent rim around the content area, in place of a strip that was permanently on screen
    /// to say what the rim says only when it is true.
    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(cells) { cell in
                    switch cell {
                    case .pending(let item):
                        PendingCell(item: item, height: Self.cellHeight)
                    case .done(let item):
                        GalleryCard(
                            item: item,
                            model: model,
                            height: Self.cellHeight,
                            isSelected: model.selection.contains(item.id),
                            highlighted: model.highlightedItemID == item.id
                        )
                    }
                }
            }
            .padding(16)
        }
        // The scroll view brings a background of its own — the system's window backdrop,
        // which is the one thing this window no longer has. Hidden, the cards sit on glass.
        .scrollContentBackground(.hidden)
        .scrollIndicators(.automatic)
        .overlay {
            if dropTarget.isTargeted {
                RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The only progress anyone can honestly report. Vision runs a single opaque request
    /// per image with no callback, so the per-row "60%" in the mockup would be a spinner
    /// wearing a number.
    private func progress(_ batch: BatchProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: L.s("%1$d of %2$d done"), batch.done, batch.total))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: batch.fraction)
                .progressViewStyle(.linear)
                .tint(Palette.coral)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// The empty state, standing directly on the glass.
    ///
    /// It used to be a dashed rectangle over a `.quaternary` wash — the standing drop banner
    /// the gallery pass deleted, grown to fill the window. Two reasons it goes now: the wash
    /// is a system-grey fill on a surface whose whole point is that it takes its colour from
    /// what is behind it, and the dash is a hairline inside a panel, which v2 bans everywhere
    /// else in the app. What answers a drag is the same accent rim the grid uses, and it says
    /// it only when it is true.
    private var dropZone: some View {
        let targeted = dropTarget.isTargeted
        return VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(.bottom, 4)
            Text(L.s("Drop images here"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            Text(L.s("or press ⌘V to paste"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        // The window is resizable down to 480pt and the empty state is two sentences: they
        // wrap and centre rather than being cut off at the window's edge.
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Color.accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(targeted ? 1 : 0)
        }
        .padding(16)
    }

    /// The offline claim used to live here. It is a standing fact about the product, not a
    /// status, and it is already stated in Settings and in About — repeating it under every
    /// batch made it wallpaper.
    ///
    /// The cutout count that replaced it has gone the same way: the grid is *made of* the
    /// cutouts, and a number counting the things the user is looking at is a caption on a
    /// photograph saying "photograph". What is left is the line that only speaks when
    /// something has happened, and the verb.
    ///
    /// And no `.bar` under them. A material strip is how you separate a footer from an
    /// opaque content area; on glass it is a second, greyer pane of glass laid over the
    /// first, which is the giveaway that a surface was assembled from stock parts. The
    /// status line and the button stand on the window's own substance.
    private var bottomBar: some View {
        HStack(spacing: 8) {
            if let status = model.status {
                statusIcon(status.kind)
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.kind == .warning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !model.recents.items.isEmpty {
                // Coral, as in p2. §4.7's one-tint-per-screen rule is about the accent not
                // being spent on decoration; the progress bar and the primary action are the
                // same voice saying "this is the thing in motion and the thing to press",
                // which is how p2 draws them. It was changed to the system accent in an
                // earlier pass by reading the rule as a headcount — that was the mistake.
                // A large capsule, not a small rounded rect: it is the window's one primary
                // verb, and v2's reference products all give the single committing action a
                // body you could hit without looking.
                ExportButton(selected: model.selection.count) { model.exportTargeted() }
                    // The label changes width as the selection does, and the count is
                    // pluralised by the catalog; a fixed frame here would clip "Export 12…"
                    // in the first language whose word for it is longer than English's.
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func statusIcon(_ kind: StatusLine.Kind) -> some View {
        Group {
            switch kind {
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .info:
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }
}

/// The window's one primary verb, in whichever prominent style the system has.
///
/// `.glassProminent` on macOS 26: it is the same shape and the same coral as
/// `.borderedProminent` below it, drawn as a tinted lens instead of as a flat capsule, which
/// is what puts it in the same family as the round glass buttons on the cards above it. The
/// tint is still coral rather than the accent — §4.7's one-tint-per-screen rule is about not
/// spending the accent on decoration, and p2 draws the progress bar and the committing action
/// in the same voice on purpose.
///
/// It names what it will actually write. With a selection, "Export All…" would be a button
/// that does something other than what it says, which is the one thing a committing action
/// may never be.
private struct ExportButton: View {
    let selected: Int
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            base.buttonStyle(.glassProminent)
        } else {
            base.buttonStyle(.borderedProminent)
        }
    }

    private var title: String {
        // Through the catalog, plural and all: "Export 1…" is a different string from
        // "Export 4…" in most of the languages this app has not been translated into yet.
        selected == 0 ? L.s("Export All…") : L.s("Export \(selected)…")
    }

    private var base: some View {
        Button(title, action: action)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .tint(Palette.coral)
    }
}


/// A grid slot, in whichever of its two lives it is currently in — the same shape the shelf
/// uses, for the same reason: a job finishing must be a content change in one cell rather
/// than a delete from one array and an insert into another, which SwiftUI would animate as
/// the grid reflowing around the gap.
private enum GalleryCell: Identifiable {
    case pending(PendingItem)
    case done(RecentItem)

    var id: UUID {
        switch self {
        case .pending(let item): item.id
        case .done(let item): item.id
        }
    }
}

/// A finished cutout, at gallery scale.
///
/// The shelf's `CutoutCard` and nothing else: same mount, same board, same radius family, so
/// the object a user recognises in the menu-bar panel is the object they recognise here. What
/// this one adds is what a batch surface needs and a 92pt shelf tile has no room for —
/// selection, and the name and size of the file, which appear under the pointer rather than
/// standing permanently on top of the picture they describe.
private struct GalleryCard: View {
    let item: RecentItem
    let model: AppModel
    let height: CGFloat
    let isSelected: Bool
    let highlighted: Bool

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        CutoutCard(height: height, lifted: hovering) {
            ZStack {
                Checkerboard()
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(4)
                }
            }
        }
        // Top-trailing, opposite the selection mark: the pair used to sit bottom-trailing on
        // the shelf tile, and here the bottom of the card is where the caption comes up.
        .overlay(alignment: .topTrailing) {
            if hovering {
                HoverActions {
                    GlassCircleButton(symbol: "doc.on.doc", label: L.s("Copy")) { model.copy(item) }
                    GlassCircleButton(symbol: "arrow.down.to.line", label: L.s("Save")) { model.save(item) }
                }
                .padding(Tokens.cardPadding)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if hovering { caption.transition(.opacity) }
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionBadge()
                    .padding(Tokens.cardPadding + 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // A rim, not a wash: a selected card that goes blue all over hides the one thing the
        // user selected it for. Accent for the selection, coral for the de-duplication flash —
        // the two never mean the same thing, and the flash wins the corner it lands in.
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(highlighted ? Palette.coral : Color.accentColor, lineWidth: 2)
                .opacity(highlighted || isSelected ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.22), value: highlighted)
        .animation(.easeOut(duration: Tokens.hoverDuration), value: isSelected)
        .onHover { on in
            withAnimation(.easeOut(duration: Tokens.hoverDuration)) { hovering = on }
        }
        .onAppear { thumbnail = NSImage(data: item.thumbnailPNG) }
        // Double first, so a double-click opens the preview instead of selecting and then
        // opening. ⌘ is read from the event stream rather than from a `.modifiers` gesture:
        // `TapGesture().modifiers(.command)` and a plain `onTapGesture` on the same view
        // resolve against each other unpredictably, and the flags at the moment of the tap
        // are the same fact by a shorter route.
        .onTapGesture(count: 2) { model.preview(item) }
        .onTapGesture { model.select(item, extending: NSEvent.modifierFlags.contains(.command)) }
        .onDrag { item.dragProvider() }
        .contextMenu {
            Button(L.s("Copy Image")) { model.copy(item) }
            Button(L.s("Save As…")) { model.save(item) }
            Button(L.s("Show Preview")) { model.preview(item) }
            Divider()
            Button(L.s("Delete"), role: .destructive) { model.discard(item) }
        }
        .accessibilityElement(children: .combine)
        // The whole caption, not just the name: VoiceOver has no hover, so this is the only
        // place the size and the engine can be said at all.
        .accessibilityLabel(GalleryCaption.text(
            name: item.suggestedName,
            width: item.pixelWidth,
            height: item.pixelHeight,
            engine: EngineLabels.mark(item.engineID)
        ))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Name and size, and the engine when it was not the default one — the row subtitle's
    /// facts, minus the timestamp, which was the least useful of them in a list already
    /// ordered by time.
    ///
    /// It floats up on hover instead of living under the card. A caption below every cell
    /// would push the grid apart into a table of contents, and the file's name is not what
    /// the user is scanning for: the picture is.
    private var caption: some View {
        // Two `Text`s, so the name is what gives way. The size is four characters and an ×,
        // and it is the fact that survives being read at a glance; a filename that has lost
        // its last three letters is still the file.
        HStack(spacing: 0) {
            Text(verbatim: item.suggestedName)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(verbatim: " · " + GalleryCaption.detail(
                width: item.pixelWidth,
                height: item.pixelHeight,
                engine: EngineLabels.mark(item.engineID)
            ))
            .lineLimit(1)
            .layoutPriority(1)
        }
        .font(.caption2)
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pluckGlass(in: RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous), fallback: .thinMaterial)
        .padding(Tokens.cardPadding)
        .allowsHitTesting(false)
    }
}

/// The corner mark that says "this one". Filled, because an outline circle on a photograph is
/// a shape the eye has to find; and small, because the rim around the card is already carrying
/// the state at a glance — this is what disambiguates it from the coral de-duplication flash.
private struct SelectionBadge: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor)
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
        .pluckShadow(Tokens.cardShadow)
        .accessibilityHidden(true)
    }
}
