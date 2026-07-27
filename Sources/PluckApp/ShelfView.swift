import AppKit
import SwiftUI

/// Contents of the menu-bar shelf. No `Divider()` anywhere: §4.7 rule ② says regions are
/// separated by spacing and material, and the bottom bar floats over the grid rather than
/// sitting in a partitioned row.
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
    /// About, not Settings. v0.1 has nothing to configure — the engine is fixed, the output
    /// format is fixed, and there is no shortcut to rebind — so a gear here would be a
    /// control that promises a surface the app does not have.
    var onAbout: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

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
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Palette.coral, lineWidth: 2)
                    .background(Palette.coral.opacity(0.08))
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
        HStack(spacing: 10) {
            Image(systemName: model.statusMessage == nil ? "square.and.arrow.down.on.square" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(model.statusMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            Text(model.statusMessage ?? L.s("Drop or paste images here"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private var recentHeader: some View {
        HStack(spacing: 0) {
            Text(L.s("Recent"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if !model.recents.items.isEmpty {
                ClearButton { model.clearRecents() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
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
                Text(L.s("Cutouts you make in this session show up here."))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
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
                    .padding(.horizontal, 14)
                    // Room for the floating bar, which overlaps the scroll area by design.
                    .padding(.bottom, Self.barHeight + 10)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button(L.s("Quit"), action: onQuit)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
            Spacer(minLength: 8)
            GlassCircleButton(symbol: "info.circle", label: L.s("About Pluck"), action: onAbout)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.barHeight)
        .background(.ultraThinMaterial)
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
            .font(.subheadline)
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
                    .padding(6)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            if hovering {
                HStack(spacing: 0) {
                    GlassCircleButton(symbol: "doc.on.doc", diameter: 24, label: L.s("Copy")) { model.copy(item) }
                    Spacer(minLength: 4)
                    GlassCircleButton(symbol: "arrow.down.to.line", diameter: 24, label: L.s("Save")) { model.save(item) }
                }
                .padding(7)
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
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
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
                    .padding(6)
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
