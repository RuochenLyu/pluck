import AppKit
import PluckKit
import SwiftUI

/// The preview, as a standard inspector pane — Finder's grammar for "details of what is
/// selected". It replaces the floating borderless panel, which had to manage its own
/// position, level, drag region and close button; the inspector gets all of that from the
/// window it belongs to, and it stays next to the grid it describes.
struct PreviewInspectorView: View {
    let model: AppModel

    var body: some View {
        if let item = model.previewedItem {
            ItemInspector(item: item, model: model)
                // A new identity per item: the slider position, the decoded halves and the
                // engine list all belong to one cutout.
                .id(item.id)
        } else {
            ContentUnavailableView(
                L.s("No Cutout Selected"),
                systemImage: "photo.on.rectangle",
                description: Text(L.s("Click a cutout to compare it with the original."))
            )
        }
    }
}

private struct ItemInspector: View {
    let item: RecentItem
    let model: AppModel

    @State private var options: [AppModel.EngineOption] = []

    /// What the engine switcher's contents depend on: the grid — a re-pluck landing or a
    /// model finishing its download changes what the menu should say.
    private var optionsKey: Int { model.recents.items.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ComparisonSlider(item: item)
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous))

                details

                actions
            }
            .padding(14)
        }
        .task(id: optionsKey) {
            options = await model.engineOptions(for: item)
        }
    }

    private var aspect: CGFloat {
        let width = CGFloat(max(item.pixelWidth, 1))
        let height = CGFloat(max(item.pixelHeight, 1))
        return width / height
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: item.suggestedName)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(verbatim: "\(item.pixelWidth) × \(item.pixelHeight)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Which engine this picture is being looked at through — a standing switch, not a verb.
    /// Switching to an engine this picture has already been through costs nothing (the pane
    /// just points at the cutout that exists); a new combination re-plucks, and an engine
    /// that is not installed says what it will cost to download.
    @ViewBuilder private var engineRow: some View {
        LabeledContent {
            if model.isRepluckRunning(item) {
                ProgressView()
                    .controlSize(.small)
            } else if !options.isEmpty {
                Picker(L.s("Engine"), selection: engineSelection) {
                    ForEach(options) { option in
                        Text(option.menuTitle).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            } else {
                Text(verbatim: EngineLabels.name(item.engineID))
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(L.s("Engine"))
        }
    }

    private var engineSelection: Binding<String> {
        Binding(
            get: { item.engineID },
            set: { model.showEngine($0, for: item) }
        )
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            engineRow
            HStack(spacing: 8) {
                Button(L.s("Copy")) { model.copy(item) }
                Button(L.s("Save…")) { model.save(item) }
                    .keyboardShortcut("s", modifiers: .command)
                Spacer()
                Button(L.s("Delete"), role: .destructive) { model.discard(item) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Before/after wipe. Two identically-fitted layers stacked, the top one masked to the
/// right of the handle: because the cutout has exactly the source image's dimensions,
/// `scaledToFit` in the same frame puts every pixel of both layers on top of each other,
/// so the mask edge is the only thing the eye tracks.
struct ComparisonSlider: View {
    let item: RecentItem

    @State private var fraction: CGFloat = 0.5
    @State private var before: NSImage?
    @State private var after: NSImage?

    var body: some View {
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
        .overlay(alignment: .bottomLeading) {
            sideLabel(L.s("Original"), visible: Self.labels(at: fraction).original)
        }
        .overlay(alignment: .bottomTrailing) {
            sideLabel(L.s("Cutout"), visible: Self.labels(at: fraction).cutout)
        }
        .task(id: item.id) {
            // Both halves are files, and `Data(contentsOf:)` blocks. Reading them on the
            // main actor would stall the click that opened the pane; the images arrive a
            // frame later instead.
            let item = item
            let maxEdge = Self.decodeMaxEdge
            let bytes = await Task.detached(priority: .userInitiated) {
                (item.originalPNG(), PluckService.fitted(item.pngData(), maxEdge: maxEdge))
            }.value
            before = bytes.0.flatMap(NSImage.init(data:))
            after = bytes.1.flatMap(NSImage.init(data:))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.s("Compare original and cutout"))
    }

    /// The pane decodes at its own scale, not the cutout's: an inspector column is at most
    /// ~480pt, and decoding a 24-megapixel export to draw half a megapixel held two
    /// full-resolution images in memory for nothing.
    static let decodeMaxEdge = 1120

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

    /// Which half is which. A label goes away when the handle is about to run it over: the
    /// alternative is a caption sitting on top of the seam it is describing.
    static func labels(at fraction: CGFloat) -> (original: Bool, cutout: Bool) {
        let clearance: CGFloat = 0.18
        return (original: fraction > clearance, cutout: fraction < 1 - clearance)
    }

    private func sideLabel(_ text: String, visible: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .padding(8)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: visible)
            .allowsHitTesting(false)
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
                .background(.regularMaterial, in: Circle())
                .pluckShadow(Tokens.controlShadow)
        }
        .position(x: width * fraction, y: height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
