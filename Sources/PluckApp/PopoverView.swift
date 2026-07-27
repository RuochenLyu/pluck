import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    static let size = CGSize(width: 340, height: 440)

    let model: AppModel
    var onQuit: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            dropZone
                .padding(12)
            Divider()
            recentSection
            Divider()
            bottomBar
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.quaternary)
            .frame(height: 108)
            .overlay {
                HStack(spacing: 14) {
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(L.s("Drop image or ⌥⌘B to pluck clipboard"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
            }
            .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                load(providers)
                return true
            }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.s("Recent"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            if model.recents.items.isEmpty {
                Text(L.s("Cutouts you make in this session show up here."))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(model.recents.items) { item in
                            RecentCell(item: item, model: model)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bottomBar: some View {
        HStack {
            Button(L.s("Quit"), action: onQuit)
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.s("Settings"))
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in model.handleDrop([.file(url)]) }
            }
            if !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadDataRepresentation(for: .image) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in model.handleDrop([.data(data)]) }
                }
            }
        }
    }
}

private struct RecentCell: View {
    let item: RecentItem
    let model: AppModel

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
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            if hovering {
                HStack {
                    cellButton("doc.on.doc", label: L.s("Copy")) { model.copy(item) }
                    Spacer()
                    cellButton("arrow.down.to.line", label: L.s("Save")) { model.save(item) }
                }
                .padding(8)
            }
        }
        .onHover { hovering = $0 }
        .onAppear { thumbnail = NSImage(data: item.thumbnailPNG) }
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
    }

    private func cellButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Transparency is the product; the checkerboard is content, not chrome, so it is drawn
/// flat with no material behind it (product-plan §4.7).
private struct Checkerboard: View {
    var square: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let dark = Color(white: 0.87)
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : square
                while x < size.width {
                    context.fill(
                        Path(CGRect(x: x, y: y, width: square, height: square).intersection(CGRect(origin: .zero, size: size))),
                        with: .color(dark)
                    )
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
        .drawingGroup()
    }
}
