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
    private static let inset: CGFloat = Tokens.panelInset

    let model: AppModel
    /// Driven by the panel's AppKit drag destination — the whole shelf is the drop target,
    /// not just the strip: aiming a dragged file at a 40pt bar is a worse deal than
    /// dropping on the surface already under it.
    let dropTarget: DropTarget
    /// The gear is back, and this time it opens something. It was removed in v0.1 because
    /// there was nothing to configure; the history switch and the offline statement are
    /// enough to earn it.
    ///
    /// It opens Settings on the click, with no menu in between: a gear means settings
    /// everywhere else on this machine, and a pull-down that exists to hold one more item
    /// than it needs makes the common case cost two clicks. About and Quit live on the
    /// status item's right-click menu, which is where a menu-bar app is looked for.
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
                RoundedRectangle(cornerRadius: Tokens.panelRadius)
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
            PlainIconButton(symbol: "gearshape", label: L.s("Settings"), action: onSettings)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, Tokens.panelTopInset)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous))
            .padding(Self.inset - 8)
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
        .overlay { DashedOutline(cornerRadius: Tokens.cardRadius, accented: dropTarget.isTargeted) }
        .padding(.horizontal, Self.inset)
        .padding(.bottom, Self.inset)
        .accessibilityElement(children: .combine)
    }
}

/// The dashed container, in both its sizes. It has to read as a held-open space rather than
/// as a control with a border — and it is the one dashed line v2's "no hairlines" rule
/// keeps, because it is not dividing anything: it is the shape of an absence.
///
/// A touch stronger than the quarter-opacity it used to be. The panel is more transparent
/// now (`.hudWindow`), and a 25%-secondary dash over a busy wallpaper disappeared entirely.
private struct DashedOutline: View {
    var cornerRadius: CGFloat
    var accented: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                accented ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.35)),
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
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(accented ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            Text(L.s("⌘V"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // Same radius as the cards it stands in line with: the ghost is a slot in the grid,
        // and a slot with a tighter corner than the things that land in it reads as a
        // different kind of object.
        .overlay { DashedOutline(cornerRadius: Tokens.cardRadius, accented: accented) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// The mount every grid slot sits on (visual language v2, from p3).
///
/// A cutout used to be a checkerboard rectangle clipped to a radius, floating directly on
/// the panel — which meant the grid was a set of holes in the glass. p3 draws the opposite:
/// solid light cards, with the board and the subject *inside* them. That reading is what
/// makes a transparent PNG look like an object you can pick up, and it is also what gives
/// the hover lift something to lift.
private struct CutoutCard<Content: View>: View {
    let height: CGFloat
    var lifted: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbnailRadius, style: .continuous))
            .padding(Tokens.cardPadding)
            .frame(height: height)
            .background(
                Palette.cardSurface,
                in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
            )
            .pluckShadow(lifted ? Tokens.cardHoverShadow : Tokens.cardShadow)
            .scaleEffect(lifted ? Tokens.hoverLift : 1)
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
        // Bottom-trailing, not centred: p3 puts the pair in the corner, which leaves the
        // middle of the picture — the part the user is looking at to decide — uncovered.
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                HoverActions {
                    GlassCircleButton(symbol: "doc.on.doc", label: L.s("Copy")) { model.copy(item) }
                    GlassCircleButton(symbol: "arrow.down.to.line", label: L.s("Save")) { model.save(item) }
                }
                .padding(Tokens.cardPadding)
                .transition(.opacity)
            }
        }
        // The one coral moment in the grid: a re-pluck that de-duplicated into this cell.
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(Palette.coral, lineWidth: 2)
                .opacity(highlighted ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.22), value: highlighted)
        .onHover { on in
            withAnimation(.easeOut(duration: Tokens.hoverDuration)) { hovering = on }
        }
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
        CutoutCard(height: height) {
            ZStack {
                Checkerboard()
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(4)
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
                // The rim says "this one"; the glyph says "this failed". Without it the cell
                // is only distinguishable from the de-duplication flash by its colour, and
                // the two are three grid slots and 900ms apart.
                if item.failure != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.red)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .transition(.opacity)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
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
