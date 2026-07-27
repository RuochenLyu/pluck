import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    static let size = CGSize(width: 340, height: 440)

    let model: AppModel
    var onQuit: () -> Void
    var onSettings: () -> Void

    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            dropHint
            Divider()
            recentSection
            Divider()
            bottomBar
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The whole popover is the drop target, not just the strip: aiming a dragged file
        // at a 40pt bar is a worse deal than dropping on the surface already under it.
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            load(providers)
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
    }

    /// One line, ≤44pt: the drop affordance is a hint, not an empty state — the empty
    /// state belongs to the Recent grid below.
    private var dropHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 13, weight: .regular))
            Text(L.s("Drop or paste images here"))
                .font(.callout)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 40)
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
        .onTapGesture { model.preview(item) }
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L.s("Preview cutout"))
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
