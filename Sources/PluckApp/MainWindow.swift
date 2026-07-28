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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                    style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [6, 5])
                )
        }
        .padding(16)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    switch row {
                    case .pending(let item):
                        PendingRow(item: item)
                    case .done(let item):
                        ResultRow(item: item, model: model)
                    }
                    if row.id != rows.last?.id {
                        // Flush with the text column: 16 of row padding, 44 of thumbnail,
                        // 12 of gap.
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .padding(.vertical, 4)
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
                Button(L.s("Export All…")) { model.exportAll() }
                    .buttonStyle(.borderedProminent)
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
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13, weight: .regular))
            Text(L.s("Drop images here"))
                .font(.callout)
        }
        .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(targeted ? Color.accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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

    @State private var thumbnail: NSImage?
    @State private var hovering = false

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
                    createdAt: item.createdAt
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer(minLength: 8)
            // No tick on the successful rows. Every row in this list succeeded — the ones
            // that did not are `PendingRow`s wearing a red triangle — so a checkmark on
            // each one is a column of punctuation that carries no information.
            if hovering {
                HoverActions {
                    GlassCircleButton(symbol: "doc.on.doc", diameter: 26, label: L.s("Copy")) { model.copy(item) }
                    GlassCircleButton(symbol: "arrow.down.to.line", diameter: 26, label: L.s("Save")) { model.save(item) }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .task(id: item.thumbnail) {
            thumbnail = item.thumbnail.flatMap { NSImage(data: $0) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.failure?.message ?? L.s("Plucking…"))
    }
}

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
                    .padding(4)
                    .saturation(dimmed ? 0 : 1)
                    .opacity(dimmed ? 0.55 : 1)
            }
        }
        .frame(width: rowThumbnailSide, height: rowThumbnailSide)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
