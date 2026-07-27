import SwiftUI

/// Transparency is the product; the checkerboard is content, not chrome, so it is drawn
/// flat with no material behind it (product-plan §4.7).
struct Checkerboard: View {
    var square: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let dark = Color(white: 0.87)
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
}
