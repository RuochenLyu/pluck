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

/// Material pill for a label floating over content — rule ④ of §4.7: no system title bar,
/// the title rides on top of the image instead.
struct GlassCapsule<Content: View>: View {
    var horizontal: CGFloat = 10
    var vertical: CGFloat = 5
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
    }
}
