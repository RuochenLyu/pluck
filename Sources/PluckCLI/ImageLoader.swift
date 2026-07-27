import CoreGraphics
import Foundation
import ImageIO
import PluckKit

/// Decoding is ImageIO-only: whatever the system can read (jpg/png/heic/tiff/webp/…)
/// the CLI can read, with no AppKit anywhere near the process.
enum ImageLoader {
    static func load(contentsOf path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PluckError.imageLoadFailed(reason: "unsupported or unreadable file")
        }
        return try decode(source)
    }

    static func load(data: Data) throws -> CGImage {
        guard !data.isEmpty else {
            throw PluckError.imageLoadFailed(reason: "no data on stdin")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PluckError.imageLoadFailed(reason: "unrecognized image data")
        }
        return try decode(source)
    }

    private static func decode(_ source: CGImageSource) throws -> CGImage {
        guard CGImageSourceGetCount(source) > 0 else {
            throw PluckError.imageLoadFailed(reason: "file contains no image")
        }

        // Camera JPEG/HEIC store rotation in EXIF; decoding the raw pixels would export a
        // sideways cutout. The thumbnail path is ImageIO's own orientation-applying decoder,
        // capped at the full pixel size so it is not actually a downscale.
        if let transformed = orientedFullSize(source) { return transformed }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PluckError.imageLoadFailed(reason: "could not decode image")
        }
        return image
    }

    private static func orientedFullSize(_ source: CGImageSource) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientation = properties[kCGImagePropertyOrientation] as? Int,
              orientation > 1,
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
