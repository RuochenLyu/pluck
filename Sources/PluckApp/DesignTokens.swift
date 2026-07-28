import AppKit
import SwiftUI

/// The numbers behind visual language v2.
///
/// These figures come from holding p3 (`docs/prototypes/p3-menubar.png`) next to Dropover
/// and Yoink and measuring the difference: bigger radii, bigger controls, filled surfaces
/// doing the work that hairlines used to do, and a checkerboard quiet enough to read as
/// "nothing here" rather than as pattern. **Changing a number here changes it everywhere —
/// that is the point of the file.**
///
/// Three rules the values encode, so a later edit knows what it is trading away:
///
/// 1. **No hairlines inside a panel.** Regions are separated by spacing, radius and fill.
///    There is no separator token because there are no separators.
/// 2. **Radius grows with the surface.** Panel 20, card 14, chip/row 10, thumbnail 8. A
///    child never carries a radius equal to or larger than its parent's.
/// 3. **A control is at least 32pt.** Dropover's whole vocabulary is large soft shapes with
///    generous dead space; 28pt glyph buttons were the single biggest thing making Pluck
///    read as stock controls stacked in a box.
enum Tokens {
    /// Floating panels — shelf, preview. Matches `ShelfPanelController.cornerMask`.
    static let panelRadius: CGFloat = 20
    /// Result cards, the batch list container, the main window's drop zone.
    static let cardRadius: CGFloat = 14
    /// Hover fills, chips, the drop strip — anything that is a region of a surface rather
    /// than a surface of its own.
    static let rowRadius: CGFloat = 10
    /// Thumbnails and other content clipped inside a card.
    static let thumbnailRadius: CGFloat = 8

    /// The frame of card left visible around a cutout. Small on purpose: the card is a
    /// mount, not a mat.
    static let cardPadding: CGFloat = 6

    /// Round glass buttons (the primary-verb shape) and square glyph buttons alike.
    static let controlSide: CGFloat = 32
    /// The preview's floating capsule sits over the user's own picture and is the one place
    /// a control has to win a contrast fight, so it gets the larger size.
    static let toolbarControlSide: CGFloat = 36

    /// Panel content insets. The header gets a taller top so the first row of cards is not
    /// crowded against the panel's own corner radius.
    static let panelInset: CGFloat = 20
    static let panelTopInset: CGFloat = 16

    /// Checkerboard: small squares, low contrast. At 8pt and 13% the board was competing
    /// with the cutout for the eye; at 6pt and ~5% it reads as texture.
    static let checkerSquare: CGFloat = 6

    /// Card elevation, at rest and under the pointer. Both are soft and short — a card that
    /// casts a hard shadow on a glass panel reads as pasted on.
    static let cardShadow = ShadowSpec(opacity: 0.08, radius: 3, y: 1)
    static let cardHoverShadow = ShadowSpec(opacity: 0.16, radius: 8, y: 3)
    /// Controls floating directly over content, which need to separate from any picture.
    static let controlShadow = ShadowSpec(opacity: 0.20, radius: 5, y: 2)

    static let hoverLift: CGFloat = 1.02
    static let pressScale: CGFloat = 0.96
    static let hoverDuration: Double = 0.15

    // MARK: Liquid Glass (macOS 26+)

    /// How close two glass shapes have to be before the system merges them into one lens
    /// (`GlassEffectContainer` / `NSGlassEffectContainerView.spacing`).
    ///
    /// Set to the gap actually used between siblings — the preview's toolbar controls sit
    /// 4pt apart, the shelf's hover pair 6pt — so a row of glass reads as one object rather
    /// than as a line of separate pills that happen to touch. Larger values start pulling in
    /// neighbours that were meant to stay apart.
    static let glassMergeSpacing: CGFloat = 8

    /// Elevation under a glass surface. Liquid Glass draws its own edge lighting and a
    /// contact shadow of its own, so ours only has to say "this is floating" — at
    /// `controlShadow`'s weight the two stack into a dark halo, which is the giveaway that
    /// a macOS 14 shadow was left on a macOS 26 control.
    static let glassShadow = ShadowSpec(opacity: 0.10, radius: 4, y: 1)
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

extension Palette {
    /// The surface a result card is drawn on: white in light, an elevated grey in dark.
    ///
    /// Not a `Material`. A card is a solid object sitting *on* the panel's glass — giving it
    /// a material of its own would blur the wallpaper twice and leave the grid looking like
    /// frosted glass on frosted glass, which is exactly what p3's flat white cards are not.
    static let cardSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkPluck ? .pluckHex(0x3A3A3C) : .white
    })
}

extension NSAppearance {
    var isDarkPluck: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
