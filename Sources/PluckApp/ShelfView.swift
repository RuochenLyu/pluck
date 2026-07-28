import AppKit
import SwiftUI

/// What the content area is showing. Pulled out of the view because it is the one layout
/// decision with a rule worth stating: the ghost slot is either the first cell of a grid
/// or, with nothing to sit in front of, the whole invitation.
enum ShelfContent: Equatable {
    /// Nothing plucked yet. The ghost grows to fill the area and carries the copy.
    case invitation
    /// Ghost slot, then placeholders, then results.
    case grid

    static func resolve(pending: Int, recents: Int) -> ShelfContent {
        pending == 0 && recents == 0 ? .invitation : .grid
    }

    /// The section label names the grid below it, so with no grid there is nothing to name.
    var showsSectionLabel: Bool { self == .grid }
    /// The ghost is a cell only in the grid; in the empty state it *is* the content area.
    var showsGhostCell: Bool { self == .grid }

    /// Clear tracks the store, not the content: a shelf holding only in-flight placeholders
    /// is a grid with nothing yet to clear.
    static func showsClear(recents: Int) -> Bool { recents > 0 }
}

/// Contents of the menu-bar shelf.
///
/// There is no drop banner and no bottom bar. A survey of twelve menu-bar shelves
/// (Dropover, Yoink, Dropzone, Paste, CleanShot X …) turns up no standing "drop here"
/// strip in any of them: the panel *is* the target, and the invitation belongs in the
/// structure rather than in a row of chrome above it. So the first grid slot is a dashed
/// ghost — "the next one lands here" — and the three controls that used to need a bar of
/// their own sit on the section label's line, which had a whole right half spare.
///
/// No `Divider()`: §4.7 rule ② says regions are separated by spacing and material. (The one
/// below is inside a pull-down menu, where a separator is AppKit's own vocabulary.)
struct ShelfView: View {
    static let size = CGSize(width: 340, height: 452)

    private static let cellHeight: CGFloat = 92
    private static let inset: CGFloat = 16

    let model: AppModel
    /// Driven by the panel's AppKit drag destination — the whole shelf is the drop target,
    /// not just the strip: aiming a dragged file at a 40pt bar is a worse deal than
    /// dropping on the surface already under it.
    let dropTarget: DropTarget
    var onQuit: () -> Void
    var onAbout: () -> Void
    /// The gear is back, and this time it opens something. It was removed in v0.1 because
    /// there was nothing to configure; the history switch and the offline statement are
    /// enough to earn it. Quit and About moved inside it: a bar with a word-button, two
    /// bordered icons and a gear was four controls competing for a strip that has one
    /// primary job.
    var onSettings: () -> Void
    /// The way to the batch window. The shelf is a 340pt panel that dismisses on any click
    /// outside itself — fine for one image, wrong for forty rows the user wants to work
    /// through — so the two surfaces need a door between them.
    var onMainWindow: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var content: ShelfContent {
        .resolve(pending: model.pendingItems.count, recents: model.recents.items.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            contentArea
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay(alignment: .bottom) { statusStrip }
        .overlay {
            if dropTarget.isTargeted {
                // Circular, not `.continuous`: this rim has to sit exactly inside the
                // panel's mask image, which is a plain rounded rect.
                // Accent, like every other drag-targeting response; coral is reserved
                // for the dedup highlight, the one moment that is genuinely ours.
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.12), value: dropTarget.isTargeted)
    }

    /// The label and every control the shelf owns, on one line. The section label is a
    /// label, not a heading — small caps at caption size says "the grid below is Recent"
    /// without competing with the cutouts for the eye — and it leaves two thirds of the
    /// line free, which is exactly the room the deleted bottom bar was asking for.
    private var header: some View {
        HStack(spacing: 8) {
            if content.showsSectionLabel {
                Text(L.s("Recent"))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if ShelfContent.showsClear(recents: model.recents.items.count) {
                ClearButton { model.clearRecents() }
            }
            PlainIconButton(symbol: "macwindow", label: L.s("Open main window"), action: onMainWindow)
            ShelfMenuButton(onAbout: onAbout, onSettings: onSettings, onQuit: onQuit)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// A failure still needs a sentence, and the strip that used to hold one is gone. This
    /// is the same line, minus the nine tenths of its life it spent repeating advice: it
    /// exists only while there is something to say, floating over the grid rather than
    /// reserving a band of the panel against the chance of bad news.
    @ViewBuilder private var statusStrip: some View {
        if let status = model.status {
            HStack(spacing: 8) {
                Image(systemName: status.kind == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(status.kind == .warning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(Self.inset - 4)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    /// Placeholders and results in one list, one identity space. Two sibling `ForEach`es
    /// over two arrays cannot cross-fade: a job finishing is a delete from one and an
    /// insert into the other, so SwiftUI has no reason to believe the two cells are the
    /// same thing and animates the grid reflowing around them. `AppModel` hands the result
    /// the placeholder's UUID precisely so this collapses to a content change in place.
    private var cells: [ShelfCell] {
        model.pendingItems.map(ShelfCell.pending) + model.recents.items.map(ShelfCell.done)
    }

    @ViewBuilder private var contentArea: some View {
        switch content {
        case .invitation: invitation
        case .grid: grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                if content.showsGhostCell {
                    GhostSlot(height: Self.cellHeight, accented: dropTarget.isTargeted)
                }
                ForEach(cells) { cell in
                    switch cell {
                    case .pending(let pending):
                        PendingCell(item: pending, height: Self.cellHeight)
                    case .done(let item):
                        RecentCell(
                            item: item,
                            model: model,
                            height: Self.cellHeight,
                            highlighted: model.highlightedItemID == item.id
                        )
                    }
                }
            }
            .padding(.horizontal, Self.inset)
            .padding(.bottom, Self.inset)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The ghost slot at full size. Same grammar — dashed outline, no fill — so the first
    /// cutout does not change the language of the panel, only the scale of it. A filled
    /// panel would be the banner again, wearing the empty state as a disguise.
    private var invitation: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(dropTarget.isTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .padding(.bottom, 2)
            Text(L.s("Drop or paste images here"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L.s("or press ⌘V to paste"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { DashedOutline(cornerRadius: 12, accented: dropTarget.isTargeted) }
        .padding(.horizontal, Self.inset)
        .padding(.bottom, Self.inset)
        .accessibilityElement(children: .combine)
    }
}

/// The dashed container, in both its sizes. Secondary at a quarter opacity: it has to read
/// as a held-open space rather than as a control with a border.
private struct DashedOutline: View {
    var cornerRadius: CGFloat
    var accented: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                accented ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
    }
}

/// Where the next cutout will appear. Deliberately not a button: it makes no promise it can
/// keep — there is nothing to open a file panel *for* — and a dashed rectangle that responds
/// to a click would teach the user to click the one part of the shelf that does nothing.
/// It joins the whole-panel accent when a drag is overhead, which is the only moment it has
/// anything to say.
private struct GhostSlot: View {
    let height: CGFloat
    let accented: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(accented ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            Text(L.s("⌘V"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay { DashedOutline(cornerRadius: 10, accented: accented) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The gear, as a menu. ⌘, and ⌘Q are declared here rather than on a hidden button so the
/// shelf shows the shortcuts it answers instead of the user having to know them.
private struct ShelfMenuButton: View {
    var onAbout: () -> Void
    var onSettings: () -> Void
    var onQuit: () -> Void

    @State private var hovering = false

    var body: some View {
        Menu {
            Button(L.s("About Pluck"), action: onAbout)
            Button(L.s("Settings…"), action: onSettings)
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button(L.s("Quit Pluck"), action: onQuit)
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            PlainIconGlyph(symbol: "gearshape", highlighted: hovering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { on in
            withAnimation(.easeOut(duration: 0.12)) { hovering = on }
        }
        .accessibilityLabel(L.s("Menu"))
        .help(L.s("Menu"))
    }
}

/// A grid slot, in whichever of its two lives it is currently in.
private enum ShelfCell: Identifiable {
    case pending(PendingItem)
    case done(RecentItem)

    var id: UUID {
        switch self {
        case .pending(let item): item.id
        case .done(let item): item.id
        }
    }
}

/// Secondary action, so it is a text button (§4.7 rule ③) — the round glass buttons are
/// reserved for the primary verbs.
private struct ClearButton: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(L.s("Clear"), action: action)
            .buttonStyle(.plain)
            // Caption, like the section label it sits beside — but not small-capped: this
            // one is pressable, and a label and a control that look identical are a trap.
            .font(.caption)
            .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .onHover { hovering = $0 }
    }
}

private struct RecentCell: View {
    let item: RecentItem
    let model: AppModel
    let height: CGFloat
    let highlighted: Bool

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Checkerboard()
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(8)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            if hovering {
                HoverActions {
                    GlassCircleButton(symbol: "doc.on.doc", diameter: 24, label: L.s("Copy")) { model.copy(item) }
                    GlassCircleButton(symbol: "arrow.down.to.line", diameter: 24, label: L.s("Save")) { model.save(item) }
                }
                .padding(8)
            }
        }
        // The one coral moment in the grid: a re-pluck that de-duplicated into this cell.
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.coral, lineWidth: 2)
                .opacity(highlighted ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.22), value: highlighted)
        .onHover { hovering = $0 }
        .onAppear { thumbnail = NSImage(data: item.thumbnailPNG) }
        .onTapGesture { model.preview(item) }
        .onDrag { item.dragProvider() }
        // The hover buttons are two of these four and only appear under the pointer; the
        // menu is where the other two live, and it is also the only one of the two
        // vocabularies a keyboard or a right-hand-only user can reach.
        .contextMenu {
            Button(L.s("Copy Image")) { model.copy(item) }
            Button(L.s("Save As…")) { model.save(item) }
            Button(L.s("Show Preview")) { model.preview(item) }
            Divider()
            Button(L.s("Delete"), role: .destructive) { model.discard(item) }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L.s("Preview cutout"))
    }
}

/// The wait, given a place to stand. Input thumbnail desaturated and dimmed under a
/// looping sweep; the spinner only joins after 250ms so a fast pluck does not flash one.
private struct PendingCell: View {
    let item: PendingItem
    let height: CGFloat

    @State private var thumbnail: NSImage?
    @State private var sweep: CGFloat = 0
    @State private var showsSpinner = false

    var body: some View {
        ZStack {
            Checkerboard()
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(8)
                    .saturation(0)
                    .opacity(0.55)
            }
            if item.state == .running {
                sweepLight
                if showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                }
            }
            // The rim says "this one"; the glyph says "this failed". Without it the cell is
            // only distinguishable from the de-duplication flash by its colour, and the two
            // are three grid slots and 900ms apart.
            if item.failure != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .transition(.opacity)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.red, lineWidth: 2)
                .opacity(item.failure == nil ? 0 : 1)
        }
        .animation(.easeInOut(duration: 0.15), value: item.state)
        .task(id: item.thumbnail) {
            thumbnail = item.thumbnail.flatMap { NSImage(data: $0) }
        }
        .task(id: item.id) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) { showsSpinner = true }
        }
        .accessibilityLabel(item.failure?.message ?? L.s("Plucking…"))
    }

    private var sweepLight: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.white.opacity(0), .white.opacity(0.7), .white.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.6)
            .offset(x: -geo.size.width * 0.6 + sweep * geo.size.width * 1.6)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
    }
}
