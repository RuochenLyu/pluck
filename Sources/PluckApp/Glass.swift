import AppKit
import SwiftUI

/// The app's colour vocabulary. Coral is defined here and nowhere else on purpose:
/// product-plan §4.7 caps it at one tinted element per screen, and a constant that can
/// only be spelled one way is the cheapest way to keep that countable.
enum Palette {
    private static let coralRGB = (r: 1.0, g: 0.42, b: 0.31)

    static let coral = Color(red: coralRGB.r, green: coralRGB.g, blue: coralRGB.b)
    /// The status item is AppKit, and it is a separate "screen" from the shelf for the
    /// one-tint-per-screen rule: they are never both coral at the same moment.
    static let coralNS = NSColor(srgbRed: coralRGB.r, green: coralRGB.g, blue: coralRGB.b, alpha: 1)
}

/// The app's two floating surfaces, ordered. Both sit above ordinary windows because both
/// are summoned from the menu bar, so their relative order has to be stated explicitly:
/// the preview is opened *from* the shelf, and a window that appears behind the thing you
/// opened it from reads as a bug, not as depth.
extension NSWindow.Level {
    static let pluckShelf = NSWindow.Level.popUpMenu
    static let pluckPreview = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
}

/// Presses. `.buttonStyle(.plain)` gives no press feedback at all, and a 32pt target that
/// does not acknowledge the mouse-down is the one place a large soft control feels worse
/// than a small system one.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tokens.pressScale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Wordless round icon button on material — the primary-action shape in p3/p4.
///
/// "Glass" is `Material`, not `glassEffect`: `.glass` / `GlassEffectContainer` are
/// macOS 26 API and the deployment target is macOS 14. `.thickMaterial` plus a soft shadow
/// is what reads as glass on 14.
///
/// The hairline rim it used to wear is gone (visual language v2): Dropover and Yoink draw
/// no rims at all, and on a 32pt button the material and the shadow already separate it
/// from whatever is behind. Thick rather than regular material is what replaces the rim's
/// share of the contrast.
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
                .background(.thickMaterial, in: Circle())
                .pluckShadow(hovering ? Tokens.cardHoverShadow : Tokens.controlShadow)
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { on in
            withAnimation(.easeOut(duration: 0.12)) { hovering = on }
        }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Copy and Save, drawn on top of a cutout that has hover under the pointer.
///
/// It used to carry a scrim, on the theory that a material circle disappears into a white
/// product shot. The thick-material 32pt buttons carry their own contrast now, and the
/// scrim was the last plate-behind-a-plate left in the grid: p3 puts the two circles
/// straight on the picture, and so does this.
struct HoverActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
    }
}

/// The unadorned icon control: a glyph, a hover highlight, and nothing else. Chrome-free
/// because the surfaces that use it — the shelf's title line, the preview's floating
/// capsule — already have a material of their own, and a bordered box inside a material
/// bar is a second frame drawn around a button that never needed one.
///
/// The hover highlight is a circle, not a rounded square: at 32pt a squircle behind a
/// 15pt glyph is a visible box, and the panel's other pressable shapes (the glass action
/// buttons) are round. One family of shapes per surface.
struct PlainIconGlyph: View {
    let symbol: String
    var size: CGFloat = 15
    var side: CGFloat = Tokens.controlSide
    var highlighted: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: side, height: side)
            .background(Circle().fill(.quaternary).opacity(highlighted ? 1 : 0))
            .contentShape(Circle())
    }
}

struct PlainIconButton: View {
    let symbol: String
    var size: CGFloat = 15
    var side: CGFloat = Tokens.controlSide
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            PlainIconGlyph(symbol: symbol, size: size, side: side, highlighted: hovering)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { on in
            withAnimation(.easeOut(duration: 0.12)) { hovering = on }
        }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// An area that drags its window, for panels that drew their own chrome and so have no
/// title bar to grab. `WindowDragGesture` would do this in one line — it is macOS 15, and
/// the deployment target is 14. A view that answers yes to `mouseDownCanMoveWindow` is
/// what a title bar is underneath anyway.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragRegion() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragRegion: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        /// `mouseDownCanMoveWindow` alone is not enough inside SwiftUI. AppKit consults it
        /// on whatever `hitTest` hands back, and SwiftUI wraps a representable in a host
        /// view of its own whose answer is the default — no, unless the window is movable
        /// by its background, which this one deliberately is not. When that happens the
        /// event is delivered here instead, and dragging the window is then our job.
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        /// The preview is opened from the shelf, so the first click after it appears may
        /// well be the one meant to move it.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
