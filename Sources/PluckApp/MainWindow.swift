import AppKit
import SwiftUI

/// The batch surface: a real, resizable, standard-chrome window (p1/p2).
///
/// §4.7's borderless-glass rules were reverse-engineered from the *panels* — things that
/// hang off the menu bar and stand in front of the user's work for a few seconds. This is
/// the other kind of surface: it is resizable, it can be left open behind other windows,
/// and §4.7's own glass grading says so ("主窗口用标准窗口材质保可读性"). Reimplementing
/// traffic lights and a resize grip to satisfy a rule about floating panels would be
/// following the letter of the design past the point where it means anything.
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

    private func make(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L.s("Pluck")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 400)
        window.tabbingMode = .disallowed

        // The drop destination is the window's own content view rather than a SwiftUI
        // `.onDrop`: SwiftUI hands back a provider flattened to `public.jpeg` with a nil
        // `suggestedName`, and the filename is the one thing a batch list is made of.
        let backdrop = MainWindowContentView()
        backdrop.dropTarget = dropTarget
        backdrop.onDrop = { [weak self] payloads in self?.onDrop?(payloads) }

        let hosting = NSHostingView(rootView: MainWindowView(model: model, dropTarget: dropTarget))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: backdrop.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
        ])
        window.contentView = backdrop
        return window
    }
}

/// Same job as `ShelfBackdropView`, minus the material: this one sits under a window that
/// already has a background.
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

struct MainWindowView: View {
    let model: AppModel
    let dropTarget: DropTarget

    /// One list, newest first — the same order and the same identities as the shelf grid.
    /// The p2 mockup queues oldest-first, which reads well for exactly one drop and stops
    /// meaning anything the moment restored history shares the list: "first" would then be
    /// a cutout from last week.
    private var rows: [BatchRow] {
        model.pendingItems.map(BatchRow.pending) + model.recents.items.map(BatchRow.done)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let batch = model.batch, batch.total > 1, !model.pendingItems.isEmpty {
                progress(batch)
            }
            if rows.isEmpty {
                dropZone
            } else {
                // The strip survives the first drop. A window whose drop affordance
                // disappears the moment it has one row in it teaches the user that the
                // list is now a list and not a target — and then the second image goes
                // back through the menu bar.
                DropStrip(targeted: dropTarget.isTargeted)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                list
            }
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No window-level rim: the drop strip already answers the drag, and two
        // rectangles lighting up for one gesture is two voices saying one thing.
        .animation(.easeOut(duration: 0.12), value: dropTarget.isTargeted)
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
            ProgressView(value: batch.fraction)
                .progressViewStyle(.linear)
                .tint(Palette.coral)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : AnyShapeStyle(.quaternary.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(
                    targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                    style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [6, 5])
                )
        }
        .padding(16)
    }

    /// Whether the list is in the middle of a batch worth annotating (p2). One image needs
    /// no row status: its own spinner is the whole story, and a tick that appears for a
    /// second and then has to be explained away is worse than no tick.
    private var batchIsRunning: Bool {
        guard let batch = model.batch, batch.total > 1 else { return false }
        return model.isBatchRunning
    }

    /// One inset card, not full-width rows on the window's own background (p2). The card is
    /// what makes the list a list — a group of related things — rather than a stack of bands
    /// running edge to edge under a drop strip that is also edge to edge.
    private var list: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    switch row {
                    case .pending(let item):
                        PendingRow(item: item)
                    case .done(let item):
                        ResultRow(item: item, model: model, showsBatchStatus: batchIsRunning)
                    }
                }
            }
            // No inset separators between rows, and no rim around the card (visual language
            // v2). Both were drawing lines to say something the fill and the spacing already
            // said: the card's own tint marks where the list starts and stops, and a row is
            // separated from its neighbour by the 8pt of air inside it — with a rounded
            // hover fill under the pointer to make the boundary explicit at the one moment
            // it matters, which is when the user is aiming at a particular row.
            .clipShape(shape)
            .background(shape.fill(.quaternary.opacity(0.35)))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.automatic)
    }

    /// The offline claim used to live here. It is a standing fact about the product, not a
    /// status, and it is already stated in Settings and in About — repeating it under every
    /// batch made it wallpaper. What the bar can usefully say is how much is in the list,
    /// and what just happened when something did.
    private var bottomBar: some View {
        HStack(spacing: 8) {
            if let status = model.status {
                statusIcon(status.kind)
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.kind == .warning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(L.s("\(model.recents.items.count) cutouts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
                // body you could hit without looking. Coral stays — see below.
                Button(L.s("Export All…")) { model.exportAll() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .tint(Palette.coral)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.bar)
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

/// The drop affordance that outlives the empty state: a dashed strip the eye can aim at,
/// and the surface that answers a drag hovering over the window.
private struct DropStrip: View {
    let targeted: Bool

    var body: some View {
        // The paste half is not decoration: ⌘V is how a screenshot gets in, and the strip is
        // the only place in this window that can say so once the empty state is gone. Same
        // two phrases as the empty state, so the window teaches one wording, not two.
        HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13, weight: .regular))
            Text(L.s("Drop images here"))
                .font(.callout)
            Text(verbatim: "—")
                .font(.callout)
            Text(L.s("or press ⌘V to paste"))
                .font(.callout)
        }
        .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(targeted ? Color.accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous)
                .strokeBorder(
                    targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
        }
        .accessibilityElement(children: .combine)
    }
}

private enum BatchRow: Identifiable {
    case pending(PendingItem)
    case done(RecentItem)

    var id: UUID {
        switch self {
        case .pending(let item): item.id
        case .done(let item): item.id
        }
    }
}

private let rowThumbnailSide: CGFloat = 44

/// The finished article: the whole row is the drag source, so a cutout goes to another app
/// by grabbing anywhere on the line rather than by finding a 44pt square.
private struct ResultRow: View {
    let item: RecentItem
    let model: AppModel
    /// Whether a batch is running at all. Whether *this* row belongs to it is a second
    /// question, asked below.
    var showsBatchStatus = false

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    private var isInCurrentBatch: Bool {
        showsBatchStatus && model.batchItemIDs.contains(item.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            RowThumbnail(image: thumbnail, dimmed: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.suggestedName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Verbatim, or SwiftUI reads the literal as a `LocalizedStringKey`: it
                // looks the whole thing up in the catalog (where it can never be) and
                // grouping-formats the numbers on the way, so a 1024px image reports
                // itself as "1,024". Pixel counts are not prose.
                Text(verbatim: RowSubtitle.text(
                    width: item.pixelWidth,
                    height: item.pixelHeight,
                    createdAt: item.createdAt,
                    engine: EngineLabels.mark(item.engineID)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer(minLength: 8)
            // The tick is scoped to the batch in flight, not to the list. Every row here
            // succeeded — the ones that did not are `PendingRow`s wearing a red triangle —
            // so ticking all of them is a column of punctuation that says "these are
            // cutouts", which is what the window is for. While a drop is being worked
            // through, though, "which of these five is finished" is a live question, and the
            // answer belongs on the rows it is about.
            if hovering {
                HoverActions {
                    GlassCircleButton(symbol: "doc.on.doc", label: L.s("Copy")) { model.copy(item) }
                    GlassCircleButton(symbol: "arrow.down.to.line", label: L.s("Save")) { model.save(item) }
                }
                .transition(.opacity)
            } else if isInCurrentBatch {
                Label {
                    Text(L.s("Done"))
                } icon: {
                    Image(systemName: "checkmark")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // The hover fill is the row divider now. Inset and rounded so it reads as a
        // highlighted *thing* rather than as a band lit up across the card — an edge-to-edge
        // fill inside a 14pt-radius container clips against the corner on the first and last
        // row, which is how a full-width highlight announces that it is a rectangle.
        .background {
            if hovering {
                RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous)
                    .fill(.quaternary)
                    .padding(.horizontal, 6)
            }
        }
        .onHover { on in withAnimation(.easeOut(duration: 0.12)) { hovering = on } }
        .onAppear { thumbnail = NSImage(data: item.thumbnailPNG) }
        // Double-click, like a row in any other list: a single click on a row that is also
        // a drag source has to stay free, or a drag that starts a pixel late opens a panel
        // over the window the user was dragging out of.
        .onTapGesture(count: 2) { model.preview(item) }
        .onDrag { item.dragProvider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.suggestedName)
    }
}

/// p2 splits the unfinished rows into "Waiting" and a spinner. This one only spins.
///
/// Admission is `PluckQueue`'s, inside PluckKit, and it does not report which of the queued
/// jobs is holding one of its two-to-four slots — the app knows only that a job has been
/// handed over. Labelling the rows below some guessed cut-off "Waiting" would put a static
/// word on images that are at that moment being processed, which is the same class of
/// fiction as the mockup's per-image "60%". A spinner on everything unfinished is true.
private struct PendingRow: View {
    let item: PendingItem

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            RowThumbnail(image: thumbnail, dimmed: item.failure == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.failure?.message ?? L.s("Plucking…"))
                    .font(.caption)
                    .foregroundStyle(item.failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.failure == nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: item.thumbnail) {
            thumbnail = item.thumbnail.flatMap { NSImage(data: $0) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.failure?.message ?? L.s("Plucking…"))
    }
}

/// The shelf's card, at row scale: same white mount, same fine board, same radius family.
/// The two surfaces show the same objects, and a cutout that is a card in one window and a
/// bare clipped rectangle in the other is two answers to "what is this thing".
private struct RowThumbnail: View {
    let image: NSImage?
    let dimmed: Bool

    var body: some View {
        ZStack {
            Checkerboard()
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(3)
                    .saturation(dimmed ? 0 : 1)
                    .opacity(dimmed ? 0.55 : 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(3)
        .frame(width: rowThumbnailSide, height: rowThumbnailSide)
        .background(
            Palette.cardSurface,
            in: RoundedRectangle(cornerRadius: Tokens.thumbnailRadius, style: .continuous)
        )
        .pluckShadow(Tokens.cardShadow)
    }
}
