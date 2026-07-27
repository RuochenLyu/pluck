import CoreGraphics
import Foundation

/// Downsampling for display, as opposed to `ImageBuffers.downsampled(_:maxPixels:)`, which
/// exists to bound what the engine is asked to chew on. UI code thinks in points along the
/// long edge — a 320pt grid cell, a 1200pt preview — not in megapixels.
///
/// Public because it is the one piece of pixel plumbing shells legitimately need. The rest
/// of `ImageBuffers` stays internal: exporting the canonical buffer layouts would make
/// every future change to them a breaking change, for the benefit of nobody outside.
public enum Thumbnail {
    /// A copy whose longest edge is at most `maxEdge`, or the original when it already
    /// fits. Never upscales: a 40pt icon blown up to fill a grid cell looks worse than the
    /// same icon centred at its own size.
    public static func fit(_ image: CGImage, maxEdge: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxEdge, maxEdge > 0 else { return image }
        let scale = Double(maxEdge) / Double(longest)
        return try ImageBuffers.makeImage(ImageBuffers.rgba(
            from: image,
            width: max(1, Int((Double(image.width) * scale).rounded())),
            height: max(1, Int((Double(image.height) * scale).rounded()))
        ))
    }

    public static func pngData(for image: CGImage, maxEdge: Int) throws -> Data {
        try Compositor.pngData(for: fit(image, maxEdge: maxEdge))
    }
}
