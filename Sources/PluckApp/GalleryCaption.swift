import Foundation

/// The line that floats up over a gallery card on hover: which file this is, how big it is,
/// and — only when it is not the default — which engine cut it.
///
/// Pure, and a type of its own, because two of its three decisions are invisible in a
/// screenshot. The pixel count must never be group-formatted: a 1024px image that calls
/// itself "1,024" is a number pretending to be prose, and that is exactly what SwiftUI does
/// to an interpolated `Int` in a `LocalizedStringKey`. And a nil engine must drop its
/// separator with it, or every Vision cutout ends its caption in a dangling "·".
///
/// The timestamp the old row subtitle carried is gone. The grid is ordered newest-first, so
/// "2 hours ago" on each card was re-stating the position of the card in the grid, and it was
/// the one part of the line that changed under the pointer while being read.
enum GalleryCaption {
    static func text(name: String, width: Int, height: Int, engine: String? = nil) -> String {
        ([name, dimensions(width: width, height: height)] + [engine].compactMap { $0 })
            .joined(separator: " · ")
    }

    static func dimensions(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }
}
