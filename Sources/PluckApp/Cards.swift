import AppKit
import SwiftUI

/// The mount every grid slot sits on.
///
/// A cutout used to be a checkerboard rectangle floating directly on the surface — a set of
/// holes in the window. The card reading — solid light face, board and subject *inside* it —
/// is what makes a transparent PNG look like an object you can pick up, and it gives the
/// hover lift something to lift.
struct CutoutCard<Content: View>: View {
    let height: CGFloat
    var lifted: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbnailRadius, style: .continuous))
            .padding(Tokens.cardPadding)
            .frame(height: height)
            .background(
                Palette.cardSurface,
                in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
            )
            .pluckShadow(lifted ? Tokens.cardHoverShadow : Tokens.cardShadow)
            .scaleEffect(lifted ? Tokens.hoverLift : 1)
    }
}

/// The wait, given a place to stand. Input thumbnail desaturated and dimmed under a
/// looping sweep; the spinner only joins after 250ms so a fast pluck does not flash one.
struct PendingCell: View {
    let item: PendingItem
    let height: CGFloat

    @State private var thumbnail: NSImage?
    @State private var sweep: CGFloat = 0
    @State private var showsSpinner = false

    var body: some View {
        CutoutCard(height: height) {
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
