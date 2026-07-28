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

// MARK: - Liquid Glass

/// Glass, on the two systems this app runs on.
///
/// macOS 26 has real Liquid Glass — `NSGlassEffectView` in AppKit, `.glassEffect(_:in:)` and
/// `.buttonStyle(.glass)` in SwiftUI — and it is a different substance from `Material`: it
/// refracts and specularly lights the edge of its shape instead of only blurring what is
/// behind it, which is what makes a panel read as a lens over the wallpaper rather than as a
/// frosted card. The deployment target is macOS 14, where none of that exists, so **every**
/// use is written twice: `if #available(macOS 26.0, *)` for the lens, `Material` for the
/// frost. There is no deprecated back door and no `-weak_framework` trickery — the two
/// branches are simply two different designs that happen to agree about shape and size.
///
/// Where glass may *not* go is the harder half (§4.7 layering): the cutout, the checkerboard
/// and the card they sit on are the content, and a card made of glass would blur the
/// wallpaper a second time behind a picture whose whole selling point is that you can see
/// through it. Glass is for containers and controls; content stays opaque.
///
/// These helpers exist so that rule is enforced by which API a view reaches for, rather than
/// by remembering it at each call site.
extension View {
    /// A glass surface behind this view, clipped to `shape`.
    ///
    /// `fallback` is the material used on macOS 14–15; it is a parameter because the right
    /// answer differs by surface — a capsule floating over the user's photograph needs
    /// `.thickMaterial`, a status strip inside a panel that is already glass needs less.
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
/// Two reasons, both from the SDK's own note on `NSGlassEffectContainerView`: adjacent
/// lenses inside a container flow into each other instead of each drawing its own rim, and
/// the system rasterises them in one pass instead of N. A no-op below macOS 26, where there
/// are no lenses to merge.
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

/// The rounded, blurred substrate a borderless panel is drawn on — AppKit's side of the same
/// split, for the two panels whose container is a window rather than a view.
///
/// On macOS 26 this is `NSGlassEffectView`, which owns the corner radius itself: its
/// `cornerRadius` shapes the lens *and* clips what it embeds, so there is no mask image and
/// no layer rounding to keep in sync. Below that it is the `.hudWindow` + `.behindWindow`
/// visual effect view Pluck has always used, whose blur is composited by the window server
/// outside the layer tree and therefore reachable only through `maskImage`.
///
/// Both branches leave `container` — the caller's plain `NSView` — in charge of dragging
/// destinations. That separation is the point: the shelf's whole surface is a drop target,
/// and hanging that off the backdrop meant the backdrop's class was load-bearing for a
/// reason that had nothing to do with what it was made of.
@MainActor
enum PanelBackdrop {
    /// Fills `container` with a backdrop and embeds `content` in it.
    static func install(content: NSView, in container: NSView, cornerRadius: CGFloat) {
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: container.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            // Not `addSubview`: the header is explicit that only `contentView` is guaranteed
            // to land inside the effect, and an arbitrary subview may be composited over the
            // lens or under it depending on the weather.
            glass.contentView = content
            container.addSubview(glass)
        } else {
            let effect = NSVisualEffectView(frame: container.bounds)
            effect.autoresizingMask = [.width, .height]
            effect.material = .hudWindow
            effect.state = .active
            effect.blendingMode = .behindWindow
            effect.maskImage = cornerMask(radius: cornerRadius)
            // The mask shapes the material, not the views drawn on top of it, so the SwiftUI
            // side needs a clip of its own. Circular corners rather than `.continuous`: the
            // mask is a drawn `NSBezierPath` and the two shapes have to agree, or a rim drawn
            // in SwiftUI gets clipped at the corners.
            content.layer?.cornerRadius = cornerRadius
            content.layer?.masksToBounds = true
            effect.addSubview(content)
            container.addSubview(effect)
        }
    }

    /// A rounded rect just big enough to hold two corners, with cap insets so AppKit
    /// stretches the flat middle to whatever size the panel ends up.
    private static func cornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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

/// Wordless round glass button — the primary-action shape in p3/p4, and the one control in
/// the app that stands directly on the user's own picture with nothing behind it.
///
/// This is the place real Liquid Glass earns the most: a lens over a photograph picks up the
/// colours under it and lights its own rim, which is how p3 draws the pair on the camera
/// thumbnail. `.interactive()` is what makes it respond to the press the way every other
/// glass control on macOS 26 does, so `PressableButtonStyle`'s scale is dropped there — two
/// press animations on one button is one too many.
///
/// Below 26 it is `.thickMaterial` plus a soft shadow, which is what reads as glass on 14.
/// The hairline rim both versions used to wear is gone (visual language v2): Dropover and
/// Yoink draw no rims at all, and at 32pt the substance and the shadow already do the
/// separating.
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
/// It used to carry a scrim, on the theory that a material circle disappears into a white
/// product shot. The 32pt buttons carry their own contrast now, and the scrim was the last
/// plate-behind-a-plate left in the grid: p3 puts the two circles straight on the picture,
/// and so does this.
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
