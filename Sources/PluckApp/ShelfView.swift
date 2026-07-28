import AppKit
import SwiftUI

/// Contents of the menu-bar shelf. No `Divider()` in the layout: §4.7 rule ② says regions
/// are separated by spacing and material, and the bottom bar floats over the grid rather
/// than sitting in a partitioned row. (The one below is inside a pull-down menu, where a
/// separator is AppKit's own vocabulary and not ours.)
struct ShelfView: View {
    static let size = CGSize(width: 340, height: 452)

    private static let cellHeight: CGFloat = 92
    private static let barHeight: CGFloat = 52

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

    var body: some View {
        VStack(spacing: 0) {
            dropHint
            recentHeader
            grid
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay(alignment: .bottom) { bottomBar }
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

    /// One card, ≤64pt: the drop affordance is a hint, not an empty state — the empty
    /// state belongs to the Recent grid below.
    ///
    /// It doubles as the status line. A failure needs a sentence and this is the only strip
    /// wide enough for one; borrowing it costs nothing, because the hint it replaces is
    /// advice the user has visibly just finished taking.
    private var dropHint: some View {
        HStack(spacing: 8) {
            Image(systemName: hintSymbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(model.status?.kind == .warning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            Text(model.statusMessage ?? L.s("Drop or paste images here"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    /// Export All reports through this line too, so "there is a message" no longer implies
    /// "something went wrong" — the kind decides the glyph.
    private var hintSymbol: String {
        switch model.status?.kind {
        case .warning: "exclamationmark.triangle.fill"
        case .info: "checkmark.circle"
        case nil: "square.and.arrow.down.on.square"
        }
    }

    /// A section label, not a heading: small caps at caption size says "the grid below is
    /// Recent" without competing with the filenames and the drop hint for the eye.
    private var recentHeader: some View {
        HStack(spacing: 0) {
            Text(L.s("Recent"))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if !model.recents.items.isEmpty {
                ClearButton { model.clearRecents() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// Placeholders and results in one list, one identity space. Two sibling `ForEach`es
    /// over two arrays cannot cross-fade: a job finishing is a delete from one and an
    /// insert into the other, so SwiftUI has no reason to believe the two cells are the
    /// same thing and animates the grid reflowing around them. `AppModel` hands the result
    /// the placeholder's UUID precisely so this collapses to a content change in place.
    private var cells: [ShelfCell] {
        model.pendingItems.map(ShelfCell.pending) + model.recents.items.map(ShelfCell.done)
    }

    private var grid: some View {
        Group {
            if model.pendingItems.isEmpty && model.recents.items.isEmpty {
                Text(L.s("Cutouts you make show up here."))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
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
                    .padding(.horizontal, 12)
                    // Room for the floating bar, which overlaps the scroll area by design.
                    .padding(.bottom, Self.barHeight + 12)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Two controls, both borderless, both the same size. Everything that is not a door to
    /// another surface lives behind the gear.
    private var bottomBar: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            PlainIconButton(symbol: "macwindow", label: L.s("Open main window"), action: onMainWindow)
            ShelfMenuButton(onAbout: onAbout, onSettings: onSettings, onQuit: onQuit)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.barHeight)
        .background(.ultraThinMaterial)
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
