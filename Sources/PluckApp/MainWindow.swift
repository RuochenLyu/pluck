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

    /// An accessory app never shows a menu bar, so ⌘V and ⌘W have nowhere to hang and are
    /// dispatched by `AppDelegate`'s key monitor instead — which needs to know whether the
    /// event landed here.
    func owns(_ window: NSWindow?) -> Bool {
        window != nil && window === self.window
    }

    func close() {
        window?.close()
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
                list
            }
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if dropTarget.isTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.coral, lineWidth: 2)
                    .background(Palette.coral.opacity(0.06))
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.12), value: dropTarget.isTargeted)
    }

    /// The only progress anyone can honestly report. Vision runs a single opaque request
    /// per image with no callback, so the per-row "60%" in the mockup would be a spinner
    /// wearing a number.
    private func progress(_ batch: BatchProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: L.s("%1$d of %2$d done"), batch.done, batch.total))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            ProgressView(value: batch.fraction)
                .progressViewStyle(.linear)
                .tint(Palette.coral)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            Text(L.s("Drop images here"))
                .font(.title2.weight(.semibold))
            Text(L.s("or press ⌘V to paste"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
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
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.automatic)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(model.status?.text ?? L.s("100% offline — photos never leave this Mac"))
                .font(.callout)
                .foregroundStyle(model.status?.kind == .warning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            if !model.recents.items.isEmpty {
                Button(L.s("Export All…")) { model.exportAll() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.coral)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.bar)
    }

    private var statusIcon: some View {
        Group {
            switch model.status?.kind {
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .info:
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            case nil:
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
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
                Text(verbatim: "\(item.pixelWidth) × \(item.pixelHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if hovering {
                HStack(spacing: 6) {
                    GlassCircleButton(symbol: "doc.on.doc", diameter: 26, label: L.s("Copy")) { model.copy(item) }
                    GlassCircleButton(symbol: "arrow.down.to.line", diameter: 26, label: L.s("Save")) { model.save(item) }
                }
                .transition(.opacity)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
        .onHover { on in withAnimation(.easeOut(duration: 0.12)) { hovering = on } }
        .onAppear { thumbnail = NSImage(data: item.thumbnailPNG) }
        .onTapGesture { model.preview(item) }
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
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
                    .padding(3)
                    .saturation(dimmed ? 0 : 1)
                    .opacity(dimmed ? 0.55 : 1)
            }
        }
        .frame(width: rowThumbnailSide, height: rowThumbnailSide)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
