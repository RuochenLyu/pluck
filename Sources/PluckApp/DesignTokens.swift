import AppKit
import SwiftUI

/// The app's colour vocabulary. Controls follow the system accent like every other Mac
/// app; the one colour of our own is the card face, because a cutout card is a solid
/// object and `Material` would blur what is behind it.
enum Palette {
    /// The surface a result card is drawn on: white in light, an elevated grey in dark.
    static let cardSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkPluck ? .pluckHex(0x3A3A3C) : .white
    })
}

/// The few numbers the standard components do not decide for us.
///
/// Two rules the values encode:
/// 1. **Radius grows with the surface.** Card 14, row/region 10, thumbnail 8. A child
///    never carries a radius equal to or larger than its parent's.
/// 2. **Content separates by spacing and fill, not hairlines.** There is no separator
///    token because there are no separators inside our own surfaces; `Form` draws its own.
enum Tokens {
    /// Result cards and the drop zone.
    static let cardRadius: CGFloat = 14
    /// Regions of a surface — the status capsule, the comparison box.
    static let rowRadius: CGFloat = 10
    /// Thumbnails and other content clipped inside a card.
    static let thumbnailRadius: CGFloat = 8

    /// The frame of card left visible around a cutout. Small on purpose: the card is a
    /// mount, not a mat.
    static let cardPadding: CGFloat = 6

    /// The standing footer under every tile (name, size, the two quick actions). Fixed, so
    /// every card in a row bottoms out on the same line whatever its text measures.
    static let cardFooterHeight: CGFloat = 34

    /// One tile, one size. Fixed rather than stretchy: when the inspector slides in and
    /// out, fixed tiles reflow without rescaling — the rescale was the judder.
    static let tileWidth: CGFloat = 160

    /// The list view's single row height. Content is sized to fit *inside* it, because the
    /// alternating background stripes are drawn at exactly this height and a taller row
    /// puts the whole bottom of the list out of step.
    static let listRowHeight: CGFloat = 36
    static let listThumbSide: CGFloat = 26

    /// Checkerboard: small squares, low contrast. At 8pt and 13% the board was competing
    /// with the cutout for the eye; at 6pt and ~5% it reads as texture.
    static let checkerSquare: CGFloat = 6

    /// Card elevation. Soft and short — a card that casts a hard shadow reads as pasted
    /// on — and constant: tiles do not stir under the pointer.
    static let cardShadow = ShadowSpec(opacity: 0.08, radius: 3, y: 1)
    /// Controls floating directly over content (the wipe handle), which need to separate
    /// from any picture.
    static let controlShadow = ShadowSpec(opacity: 0.20, radius: 5, y: 2)
}

struct ShadowSpec {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat
}

extension View {
    func pluckShadow(_ spec: ShadowSpec) -> some View {
        shadow(color: .black.opacity(spec.opacity), radius: spec.radius, y: spec.y)
    }
}

extension NSAppearance {
    var isDarkPluck: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
