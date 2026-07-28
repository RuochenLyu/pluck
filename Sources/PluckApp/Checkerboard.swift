import AppKit
import SwiftUI

/// Transparency is the product; the checkerboard is content, not chrome, so it is drawn
/// flat with no material behind it (product-plan §4.7).
///
/// The two squares are a *pair per appearance*, not one pair dimmed: a white-and-grey board
/// under a dark UI is the brightest thing on screen and reads as a bug in the cutout rather
/// than as "nothing here". The values come from the system's own dark greys so the board
/// sits at the same depth as the surfaces around it.
struct Checkerboard: View {
    var square: CGFloat = 8

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = Self.colors(for: scheme)
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: colors.base)))
            let dark = Color(nsColor: colors.square)
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : square
                while x < size.width {
                    context.fill(
                        Path(CGRect(x: x, y: y, width: square, height: square).intersection(CGRect(origin: .zero, size: size))),
                        with: .color(dark)
                    )
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
        .drawingGroup()
    }

    /// Split out and pure so "the dark board is actually dark" is a test rather than a
    /// screenshot: `Canvas` resolves its colours itself, and a dynamic `NSColor` handed to
    /// it would be resolved against whatever appearance the drawing group happens to have.
    static func colors(for scheme: ColorScheme) -> (base: NSColor, square: NSColor) {
        switch scheme {
        case .dark: (base: .pluckHex(0x2C2C2E), square: .pluckHex(0x3A3A3C))
        default: (base: .white, square: NSColor(srgbRed: 0.87, green: 0.87, blue: 0.87, alpha: 1))
        }
    }
}

extension NSColor {
    static func pluckHex(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
