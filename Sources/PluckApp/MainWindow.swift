import AppKit
import Combine
import PluckKit
import SwiftUI

/// The one window, in standard clothes: a titled, resizable window with a unified toolbar.
///
/// The previous shape hid the title bar, filled the window with `NSGlassEffectView` and
/// hand-drew everything the system normally provides. That is exactly what Apple's Liquid
/// Glass guidance says not to do — glass belongs to the *functional* layer (toolbars,
/// sidebars, controls), which standard components render themselves; window and content
/// backgrounds stay opaque so the glass has something to stand out from. Using the standard
/// window is what buys the toolbar its glass, the scroll-edge effect, and every behaviour a
/// Mac window is expected to have, with no code here.
@MainActor
final class MainWindowController {
    private var window: PluckWindow?

    var onDrop: (([DroppedPayload]) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let dropTarget = DropTarget()

    func show(model: AppModel) {
        if window == nil {
            window = make(model: model)
            window?.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// ⌘V/⌘A/Esc/⌫ are dispatched by `AppDelegate`'s key monitor rather than by menu items —
    /// they are grid operations, not the text operations the menu would dispatch — so the
    /// monitor needs to know whether the event landed in this window.
    func owns(_ window: NSWindow?) -> Bool {
        window != nil && window === self.window
    }

    /// The toolbar and title are SwiftUI's (`sceneBridgingOptions`), and SwiftUI re-renders
    /// them itself when the language changes — nothing to do here but keep the fallback
    /// title honest for Mission Control and VoiceOver.
    func languageDidChange() {
        window?.title = L.s("Pluck")
    }

    private func make(model: AppModel) -> PluckWindow {
        let host = NSHostingController(
            rootView: MainWindowView(
                model: model,
                dropTarget: dropTarget,
                onOpenSettings: { [weak self] in self?.onOpenSettings?() }
            )
        )
        // The bridge that makes `.toolbar` drive the real NSToolbar of this AppKit window.
        host.sceneBridgingOptions = [.toolbars]

        let window = PluckWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Set for Mission Control, the Window menu and VoiceOver — but not drawn: the app
        // has no document to name, and none of the system apps this window is patterned on
        // (Notes, Freeform) spend title-bar room restating who they are.
        window.title = L.s("Pluck")
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 760, height: 540))
        window.minSize = NSSize(width: 560, height: 400)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        // The drop destination is the window itself, not a SwiftUI `.onDrop`: SwiftUI hands
        // back a provider flattened to `public.jpeg` with a nil `suggestedName`, and the
        // filename is the one thing a batch is made of. A drag that no view claims falls
        // through to the window, so registering here covers the whole surface — grid,
        // toolbar, empty state — without a custom view under the hosting controller.
        window.registerForDraggedTypes([.fileURL, .png, .tiff])
        window.dropTarget = dropTarget
        window.onDrop = { [weak self] payloads in self?.onDrop?(payloads) }
        return window
    }
}

/// The window as a dragging destination. `NSWindow` receives the `NSDraggingDestination`
/// messages for types registered on it whenever no subview claims the drag.
///
/// Every method is explicitly `@objc`, and that is the fix for a silent failure: AppKit
/// discovers a destination's abilities with `responds(to:)`, `NSWindow` does not declare
/// these selectors (which is why `override` would not compile), and a plain Swift method
/// on an NSObject subclass gets no ObjC entry point — so the window answered "no" to
/// every probe and a drop onto it did nothing at all.
final class PluckWindow: NSWindow {
    var onDrop: (([DroppedPayload]) -> Void)?
    weak var dropTarget: DropTarget?

    @objc func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // Nothing at all for a drag of our own — not even the highlight. See
        // `DroppedPayload.isForeignDrag`.
        guard DroppedPayload.isForeignDrag(source: sender.draggingSource) else { return [] }
        let accepted = !DroppedPayload.read(from: sender.draggingPasteboard).isEmpty
        setTargeted(accepted)
        return accepted ? .copy : []
    }

    @objc func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setTargeted(false)
    }

    @objc func draggingEnded(_ sender: any NSDraggingInfo) {
        setTargeted(false)
    }

    @objc func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
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

/// The gallery: a grid of cutout cards, a toolbar carrying the verbs, and a preview
/// inspector on the right — Finder's grammar, because that is the one the user already
/// knows. Selection updates the inspector; the toolbar button and double-click both open it.
struct MainWindowView: View {
    @Bindable var model: AppModel
    let dropTarget: DropTarget
    var onOpenSettings: () -> Void = {}

    /// The engines the toolbar menu can offer right now: Vision plus whatever is installed.
    /// Reloaded when the model list changes (`.pluckModelsDidChange`) — the only thing that
    /// changes it is Settings.
    @State private var engines = ModelStore()

    @FocusState private var listFocused: Bool

    /// Fixed-size tiles, adaptive count: the column count is the window's to decide, but a
    /// tile never changes size — so the inspector sliding in reflows the grid instead of
    /// rescaling every card, which was the judder. Finder's icon view works the same way.
    private static let columns = [
        GridItem(.adaptive(minimum: Tokens.tileWidth, maximum: Tokens.tileWidth), spacing: 16, alignment: .top)
    ]

    /// One list, newest first — placeholders ahead of results, so a new job appears where
    /// its result will land.
    private var cells: [GalleryCell] {
        model.pendingItems.map(GalleryCell.pending) + model.recents.items.map(GalleryCell.done)
    }

    var body: some View {
        Group {
            if cells.isEmpty {
                dropZone
            } else if model.layout == .list {
                list
            } else {
                grid
            }
        }
        .overlay(alignment: .bottom) { statusCapsule }
        .inspector(isPresented: $model.showsPreview) {
            PreviewInspectorView(model: model)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
        }
        .toolbar { toolbarContent }
        .onReceive(NotificationCenter.default.publisher(for: .pluckModelsDidChange)) { _ in
            engines.reload()
        }
        .animation(.easeOut(duration: 0.12), value: dropTarget.isTargeted)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(L.s("Add"), systemImage: "plus") { model.addImages() }
                .help(L.s("Add images"))
        }
        // The honest progress for a batch, where Notes and Mail put theirs: a small
        // spinner and a count, present only while something is actually in flight.
        if let batch = model.batch, batch.total > 1, !model.pendingItems.isEmpty {
            ToolbarItem {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(verbatim: "\(batch.done)/\(batch.total)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityLabel(String(format: L.s("%1$d of %2$d done"), batch.done, batch.total))
            }
        }
        // Everything from here rides the trailing edge — Finder's split: navigation verbs
        // on the left, the working controls on the right, air in between.
        ToolbarSpacer(.flexible)
        ToolbarItem {
            engineMenu
        }
        // One connected group, not two floating buttons — `ControlGroup` is what bridges
        // to the `NSToolbarItemGroup` Finder and Notes use for their view switchers.
        ToolbarItem {
            ControlGroup {
                Picker(L.s("View"), selection: layoutSelection) {
                    Label(L.s("Grid"), systemImage: "square.grid.2x2").tag(GalleryLayout.grid)
                    Label(L.s("List"), systemImage: "list.bullet").tag(GalleryLayout.list)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .help(L.s("View"))
        }
        ToolbarItem {
            Button(L.s("Preview"), systemImage: "sidebar.trailing") {
                model.showsPreview.toggle()
            }
            .help(L.s("Show Preview"))
        }
        // A word, not the share glyph: `square.and.arrow.up` promises the share sheet,
        // and this button writes PNG files into a folder. The count stays in the tooltip
        // so the button's width never jumps with the selection.
        ToolbarItem(placement: .primaryAction) {
            Button(L.s("Export")) { model.exportTargeted() }
                .disabled(model.recents.items.isEmpty)
                .help(exportTitle)
        }
    }

    private var exportTitle: String {
        let selected = model.selection.count
        return selected == 0 ? L.s("Export All…") : L.s("Export \(selected)…")
    }

    /// The default engine, where it can be seen — it is the product's core choice, not a
    /// buried preference. Only engines that are actually on disk are offered; getting new
    /// ones is Settings' job, one click away at the bottom of the same menu.
    private var engineMenu: some View {
        Menu {
            Picker(L.s("Engine"), selection: engineSelection) {
                ForEach(engineChoices, id: \.id) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button(L.s("Manage Models…"), action: onOpenSettings)
        } label: {
            // The word, not just a wand: which engine is the default is the product's core
            // choice, and a glyph-only menu hides the state it exists to change.
            Label(currentEngineName, systemImage: "wand.and.sparkles")
                .labelStyle(.titleAndIcon)
        }
        .help(L.s("Which engine new images use"))
    }

    private var engineChoices: [(id: String, name: String)] {
        [(EngineCatalog.defaultEngineID, EngineLabels.name(EngineCatalog.defaultEngineID))]
            + engines.rows.filter(\.isInstalled).map {
                ($0.id, EngineLabels.name($0.id, fallback: $0.descriptor.displayName))
            }
    }

    /// Reads through the same fallback the pipeline uses: a stored id whose model has been
    /// deleted shows as Vision, and only a deliberate choice stores anything.
    private var engineSelection: Binding<String> {
        Binding(
            get: {
                let stored = model.defaultEngineID
                return engineChoices.contains { $0.id == stored } ? stored : EngineCatalog.defaultEngineID
            },
            set: { model.setDefaultEngine($0) }
        )
    }

    private var currentEngineName: String {
        engineChoices.first { $0.id == engineSelection.wrappedValue }?.name
            ?? EngineLabels.name(EngineCatalog.defaultEngineID)
    }

    private var layoutSelection: Binding<GalleryLayout> {
        Binding(get: { model.layout }, set: { model.layout = $0 })
    }

    /// Finder's list view, for the batch that a grid of squares cannot hold: dozens of
    /// rows, high information density, and `List`'s own selection machinery — ⌘, ⇧, arrow
    /// keys and type-to-select all come with the component.
    ///
    /// Focused programmatically on appearance: an unfocused `List` paints its selection
    /// grey (`unemphasized`), and a view switched in by a toolbar button — which kept the
    /// focus — would show grey where Finder shows the accent.
    private var list: some View {
        List(selection: listSelection) {
            ForEach(model.pendingItems) { item in
                PendingRow(item: item)
            }
            ForEach(model.recents.items) { item in
                ListRow(item: item, model: model)
                    .tag(item.id)
            }
        }
        .scrollContentBackground(.visible)
        .alternatingRowBackgrounds(.enabled)
        // One height for real rows and the empty stripes below them: the stripes are drawn
        // at the table's row height, so a row whose content exceeds it leaves the bottom of
        // the list visibly out of step.
        .environment(\.defaultMinListRowHeight, Tokens.listRowHeight)
        .focused($listFocused)
        .task { listFocused = true }
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

    private var listSelection: Binding<Set<UUID>> {
        Binding(
            get: { model.selection.idSet },
            set: { model.applyListSelection($0) }
        )
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 16) {
                ForEach(cells) { cell in
                    switch cell {
                    case .pending(let item):
                        PendingCell(item: item)
                    case .done(let item):
                        GalleryCard(
                            item: item,
                            model: model,
                            isSelected: model.selection.contains(item.id),
                            highlighted: model.highlightedItemID == item.id
                        )
                    }
                }
            }
            .padding(20)
        }
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

    /// The empty state: the whole window is the drop target, and this is the sentence that
    /// teaches the gesture to anyone who has not performed it yet.
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

    /// A failure still needs a sentence. This is the line that exists only while there is
    /// something to say, floating over the grid rather than reserving a standing bar
    /// against the chance of bad news.
    @ViewBuilder private var statusCapsule: some View {
        if let status = model.status {
            HStack(spacing: 8) {
                Image(systemName: status.kind == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(status.kind == .warning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                Text(status.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous))
            .pluckShadow(Tokens.cardShadow)
            .padding(12)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A grid slot, in whichever of its two lives it is currently in — a job finishing must be
/// a content change in one cell rather than a delete from one array and an insert into
/// another, which SwiftUI would animate as the grid reflowing around the gap.
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

/// A finished cutout: square picture, standing footer with the name, the size and the two
/// quick actions (CleanShot's grammar) — plus the context menu, the inspector and ⌘C for
/// the same verbs by their other routes.
struct GalleryCard: View {
    let item: RecentItem
    let model: AppModel
    let isSelected: Bool
    let highlighted: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        CutoutCard {
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
        } footer: {
            HStack(spacing: 2) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.suggestedName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: sizeLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                CardFooterButton(symbol: "doc.on.doc", label: L.s("Copy")) { model.copy(item) }
                CardFooterButton(symbol: "square.and.arrow.down", label: L.s("Save")) { model.save(item) }
            }
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionBadge()
                    .padding(Tokens.cardPadding + 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // A rim, not a wash: a selected card that goes accent all over hides the one thing
        // the user selected it for. The de-duplication flash borrows the same rim — it is a
        // moment, not a state, and the badge is what disambiguates selection.
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(highlighted || isSelected ? 1 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.22), value: highlighted)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .onAppear { thumbnail = NSImage(data: item.thumbnailPNG) }
        // The single tap fires immediately; the double-click rides alongside as a
        // *simultaneous* gesture. `onTapGesture(count: 2)` stacked above a plain tap made
        // SwiftUI hold every click for the double-click timeout — the "one second to
        // select" lag. A double-click now selects on its first tap (which is what Finder
        // shows too) and opens the preview on its second.
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            model.select(
                item,
                extending: flags.contains(.command),
                ranging: flags.contains(.shift)
            )
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.preview(item) })
        .onDrag { item.dragProvider() }
        .contextMenu {
            Button { model.copy(item) } label: { Label(L.s("Copy Image"), systemImage: "doc.on.doc") }
            Button { model.save(item) } label: { Label(L.s("Save As…"), systemImage: "square.and.arrow.down") }
            Button { model.preview(item) } label: { Label(L.s("Show Preview"), systemImage: "sidebar.trailing") }
            Divider()
            Button(role: .destructive) { model.discard(item) } label: { Label(L.s("Delete"), systemImage: "trash") }
        }
        // The tooltip carries what the deleted hover caption used to: name, size, and the
        // engine when it was not the default one.
        .help(caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var caption: String {
        GalleryCaption.text(
            name: item.suggestedName,
            width: item.pixelWidth,
            height: item.pixelHeight,
            engine: EngineLabels.mark(item.engineID)
        )
    }

    /// The footer's second line: size, and the engine when it was not the default one.
    private var sizeLine: String {
        GalleryCaption.detail(
            width: item.pixelWidth,
            height: item.pixelHeight,
            engine: EngineLabels.mark(item.engineID)
        )
    }
}

/// The corner mark that says "this one". Filled, because an outline circle on a photograph
/// is a shape the eye has to find.
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


/// Finder's two shapes for the same folder.
enum GalleryLayout: String {
    case grid
    case list
}

/// A finished cutout as one line: thumbnail, name, facts. High density is the whole point —
/// this is the view for the forty-file batch, where a wall of squares stops being scannable.
private struct ListRow: View {
    let item: RecentItem
    let model: AppModel

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .padding(2)
                }
            }
            .frame(width: Tokens.listThumbSide, height: Tokens.listThumbSide)
            Text(verbatim: item.suggestedName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(verbatim: GalleryCaption.detail(
                width: item.pixelWidth,
                height: item.pixelHeight,
                engine: EngineLabels.mark(item.engineID)
            ))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            // The same two quick actions the grid's footer carries — a view switch must
            // not cost the verbs.
            CardFooterButton(symbol: "doc.on.doc", label: L.s("Copy")) { model.copy(item) }
            CardFooterButton(symbol: "square.and.arrow.down", label: L.s("Save")) { model.save(item) }
        }
        .onAppear { thumbnail = NSImage(data: item.thumbnailPNG) }
        .onDrag { item.dragProvider() }
        .contextMenu {
            Button { model.copy(item) } label: { Label(L.s("Copy Image"), systemImage: "doc.on.doc") }
            Button { model.save(item) } label: { Label(L.s("Save As…"), systemImage: "square.and.arrow.down") }
            Button { model.preview(item) } label: { Label(L.s("Show Preview"), systemImage: "sidebar.trailing") }
            Divider()
            Button(role: .destructive) { model.discard(item) } label: { Label(L.s("Delete"), systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(GalleryCaption.text(
            name: item.suggestedName,
            width: item.pixelWidth,
            height: item.pixelHeight,
            engine: EngineLabels.mark(item.engineID)
        ))
    }
}

/// A job still running, as a line. Not selectable — there is nothing to preview yet.
private struct PendingRow: View {
    let item: PendingItem

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .padding(2)
                        .saturation(0)
                        .opacity(0.55)
                }
            }
            .frame(width: Tokens.listThumbSide, height: Tokens.listThumbSide)
            Text(verbatim: item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.failure == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Spacer(minLength: 8)
            if let failure = item.failure {
                Text(failure.message)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: item.thumbnail) {
            thumbnail = item.thumbnail.flatMap { NSImage(data: $0) }
        }
        .accessibilityLabel(item.failure?.message ?? L.s("Plucking…"))
    }
}
