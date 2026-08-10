import AppKit
import SwiftUI

/// The app's colour vocabulary. The coral brand tint is gone from the UI (2026-08-10):
/// controls follow the system accent colour, like every other Mac app — the brand lives in
/// the app icon, not in the widgets. What remains here is the one colour that is not a
/// control's: the card face.
enum Palette {}

// MARK: - Liquid Glass

/// Glass, used the way the HIG says to use it: on *controls*, never as a surface.
///
/// macOS 26 has real Liquid Glass — `.glassEffect(_:in:)` and `.buttonStyle(.glass)` — and
/// standard components (the toolbar, the inspector, menus) adopt it by themselves. The only
/// custom glass left in Pluck is the pair of hover buttons that float over a cutout, which
/// is exactly the "most important functional elements" case the guidance reserves custom
/// glass for. The deployment target is macOS 14, where none of it exists, so every use is
/// written twice: the lens on 26, a `Material` below.
extension View {
    /// A glass surface behind this view, clipped to `shape`.
    @ViewBuilder
    func pluckGlass(
        in shape: some Shape,
        fallback: Material = .thickMaterial,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }
}

/// Sibling glass shapes that should be rendered — and merged — as one.
///
/// Adjacent lenses inside a container flow into each other instead of each drawing its own
/// rim, and the system rasterises them in one pass instead of N. A no-op below macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = Tokens.glassMergeSpacing
    @ViewBuilder var content: Content

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Presses. `.buttonStyle(.plain)` gives no press feedback at all, and a 32pt target that
/// does not acknowledge the mouse-down is the one place a large soft control feels worse
/// than a small system one.
struct PressableButtonStyle: ButtonStyle {
    /// False where the label is glass that already animates its own press.
    var scales = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && scales ? Tokens.pressScale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Wordless round glass button — the control that stands directly on the user's own picture
/// with nothing behind it.
///
/// This is the place real Liquid Glass earns the most: a lens over a photograph picks up the
/// colours under it and lights its own rim. `.interactive()` is what makes it respond to the
/// press the way every other glass control on macOS 26 does, so `PressableButtonStyle`'s
/// scale is dropped there — two press animations on one button is one too many.
///
/// Below 26 it is `.thickMaterial` plus a soft shadow, which is what reads as glass on 14.
struct GlassCircleButton: View {
    let symbol: String
    var diameter: CGFloat = Tokens.controlSide
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: (diameter * 0.47).rounded(), weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .pluckGlass(in: Circle(), interactive: true)
                .pluckShadow(shadow)
                .scaleEffect(hovering && !isLiquid ? 1.06 : 1)
                .contentShape(Circle())
        }
        // `.interactive()` glass shrinks and brightens under the press by itself, so ours
        // stands down rather than doubling the gesture.
        .buttonStyle(PressableButtonStyle(scales: !isLiquid))
        .onHover { on in
            withAnimation(.easeOut(duration: 0.12)) { hovering = on }
        }
        .accessibilityLabel(label)
        .help(label)
    }

    private var shadow: ShadowSpec {
        if isLiquid { return Tokens.glassShadow }
        return hovering ? Tokens.cardHoverShadow : Tokens.controlShadow
    }
}

/// Whether this machine draws Liquid Glass. Asked in view bodies where the branch is about a
/// *number* — a shadow weight, a scale factor — rather than about which view to build, which
/// is the one thing `if #available` inside a `@ViewBuilder` cannot express.
var isLiquid: Bool {
    if #available(macOS 26.0, *) { true } else { false }
}

/// Copy and Save, drawn on top of a cutout that has hover under the pointer.
///
/// The pair is a `GlassGroup` because 6pt apart is inside the merge distance: on macOS 26 the
/// two lenses flow into one another as they appear, which is the difference between a pair of
/// buttons and two buttons that happen to be adjacent.
struct HoverActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GlassGroup {
            HStack(spacing: 6) { content }
        }
    }
}
