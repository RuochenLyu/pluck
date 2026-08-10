import AppKit
import SwiftUI

/// The mount every grid slot sits on: a square picture area over a standing footer —
/// CleanShot's card grammar. The footer is what answers "what is this and what do I do
/// with it" without a hover, a hunt through a menu, or a trip to the inspector; hiding
/// every action behind the pointer was discoverability paid for with usability.
struct CutoutCard<Content: View, Footer: View>: View {
    var lifted: Bool = false
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            content
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbnailRadius, style: .continuous))
                .padding(Tokens.cardPadding)
            footer
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .frame(height: Tokens.cardFooterHeight, alignment: .center)
        }
        .background(
            Palette.cardSurface,
            in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
        )
        .pluckShadow(lifted ? Tokens.cardHoverShadow : Tokens.cardShadow)
        .scaleEffect(lifted ? Tokens.hoverLift : 1)
    }
}

/// A footer action: a small quiet glyph that brightens under the pointer. Borderless on
/// purpose — the card is the surface, and two bordered buttons in a 160pt footer would be
/// louder than the picture above them.
struct CardFooterButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.quaternary).opacity(hovering ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// The wait, given a place to stand. Input thumbnail desaturated and dimmed under a
/// looping sweep; the spinner only joins after 250ms so a fast pluck does not flash one.
struct PendingCell: View {
    let item: PendingItem

    @State private var thumbnail: NSImage?
    @State private var sweep: CGFloat = 0
    @State private var showsSpinner = false

    var body: some View {
        CutoutCard {
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
        } footer: {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.failure?.message ?? L.s("Plucking…"))
                    .font(.caption2)
                    .foregroundStyle(item.failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
