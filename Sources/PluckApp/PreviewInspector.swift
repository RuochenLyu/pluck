import AppKit
import ImageIO
import PluckKit
import SwiftUI

/// The preview, as a standard inspector pane — Finder's grammar for "details of what is
/// selected". The comparison sits on top; everything below it is a grouped `Form` of
/// `LabeledContent` rows, which is how every system inspector lays out facts, and the two
/// actions are full-width rows at the bottom, which is where a system pane puts its verbs.
struct PreviewInspectorView: View {
    let model: AppModel

    var body: some View {
        if let item = model.previewedItem {
            ItemInspector(item: item, model: model)
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

    /// What the engine switcher's contents depend on: the item, and the grid — a re-pluck
    /// landing or a model finishing its download changes what the menu should say.
    private struct OptionsKey: Equatable {
        let item: UUID
        let cutouts: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            ComparisonSlider(item: item)
                // Follows the picture's shape, but never grows past 4:3 portrait: an
                // extreme panorama or a tall crop letterboxes onto the board instead of
                // eating the whole pane.
                .aspectRatio(max(aspect, 0.75), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Form {
                Section {
                    LabeledContent(L.s("Name")) {
                        Text(verbatim: item.suggestedName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    LabeledContent(L.s("Size")) {
                        Text(verbatim: "\(item.pixelWidth) × \(item.pixelHeight)")
                            .monospacedDigit()
                    }
                    LabeledContent(L.s("Engine")) { engineControl }
                }

                Section {
                    Button { model.copy(item) } label: {
                        Label(L.s("Copy Image"), systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    Button { model.save(item) } label: {
                        Label(L.s("Save As…"), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .formStyle(.grouped)
        }
        .task(id: OptionsKey(item: item.id, cutouts: model.recents.items.count)) {
            options = await model.engineOptions(for: item)
        }
    }

    private var aspect: CGFloat {
        let width = CGFloat(max(item.pixelWidth, 1))
        let height = CGFloat(max(item.pixelHeight, 1))
        return width / height
    }

    /// Which engine this picture is being looked at through — a standing switch, not a
    /// verb. Switching to an engine this picture has already been through costs nothing
    /// (the pane just points at the cutout that exists); a new combination re-plucks, and
    /// an engine that is not installed says what it will cost to download.
    @ViewBuilder private var engineControl: some View {
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
    }

    private var engineSelection: Binding<String> {
        Binding(
            get: { item.engineID },
            set: { model.showEngine($0, for: item) }
        )
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
        // Keyed on the item: switching cutouts cancels the stale decode, resets the wipe,
        // and leaves the previous picture on screen until the next one is ready — a blank
        // flash between two selections is what reads as lag.
        .task(id: item.id) {
            fraction = 0.5
            let decoded = await ImageDecode.pair(
                before: item.originalURL,
                after: item.fileURL,
                maxEdge: Self.decodeMaxEdge
            )
            guard !Task.isCancelled else { return }
            before = decoded.before.map { NSImage(cgImage: $0, size: .zero) }
            after = decoded.after.map { NSImage(cgImage: $0, size: .zero) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.s("Compare original and cutout"))
    }

    /// The pane decodes at its own scale: an inspector column is at most ~480pt, so 1120px
    /// covers Retina. Decoding a full-size export to draw half a megapixel held two
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

/// Straight-from-disk downsampling via `CGImageSource` — decode *to* the target size in
/// one step. The previous path read the whole PNG, decoded it, re-encoded a smaller PNG,
/// and decoded that again on the main thread; the PNG re-encode alone was most of the
/// click-to-preview latency.
enum ImageDecode {
    /// `CGImage` is immutable; the compiler just cannot see that.
    struct Pair: @unchecked Sendable {
        var before: CGImage?
        var after: CGImage?
    }

    static func pair(before: URL, after: URL, maxEdge: Int) async -> Pair {
        let beforeURL = before
        let afterURL = after
        return await Task.detached(priority: .userInitiated) {
            Pair(
                before: downsampled(beforeURL, maxEdge: maxEdge),
                after: downsampled(afterURL, maxEdge: maxEdge)
            )
        }.value
    }

    nonisolated static func downsampled(_ url: URL, maxEdge: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
