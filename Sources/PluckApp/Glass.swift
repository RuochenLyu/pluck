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

/// Wordless round icon button on material — the primary-action shape in p3/p4.
///
/// "Glass" is `Material`, not `glassEffect`: `.glass` / `GlassEffectContainer` are
/// macOS 26 API and the deployment target is macOS 14. `.regularMaterial` plus a hairline
/// rim and a soft shadow is what reads as glass on 14.
struct GlassCircleButton: View {
    let symbol: String
    var diameter: CGFloat = 28
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: (diameter * 0.42).rounded(), weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(hovering ? 0.55 : 0.25), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(hovering ? 0.28 : 0.18), radius: hovering ? 5 : 3, y: 1)
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { on in
            withAnimation(.easeOut(duration: 0.12)) { hovering = on }
        }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Copy and Save, drawn on top of a cutout that has hover under the pointer.
///
/// The scrim is the point. These buttons sit over the user's own picture, which can be a
/// white product shot or a black one, and a material circle alone disappears into about
/// half of them — so the pair gets a plate of its own rather than each glyph fighting for
/// contrast separately.
struct HoverActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The unadorned icon control: a glyph, a hover highlight, and nothing else. Chrome-free
/// because the surfaces that use it — the shelf's bottom bar, the preview's floating
/// capsule — already have a material of their own, and a bordered box inside a material
/// bar is a second frame drawn around a button that never needed one.
struct PlainIconGlyph: View {
    let symbol: String
    var size: CGFloat = 15
    var side: CGFloat = 28
    var highlighted: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: side, height: side)
            .background(shape.fill(.quaternary).opacity(highlighted ? 1 : 0))
            .contentShape(shape)
    }
}

struct PlainIconButton: View {
    let symbol: String
    var size: CGFloat = 15
    var side: CGFloat = 28
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            PlainIconGlyph(symbol: symbol, size: size, side: side, highlighted: hovering)
        }
        .buttonStyle(.plain)
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
