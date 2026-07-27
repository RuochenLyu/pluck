import CoreGraphics
import CryptoKit
import Foundation
import PluckKit

struct ProcessedImage: Sendable, Equatable {
    var pngData: Data
    var thumbnailPNG: Data
    /// The *input* image, downsampled — the "before" half of the preview slider. Kept
    /// small on purpose: a session of 12 full-resolution originals in RAM is not worth a
    /// 480pt panel.
    var originalPNG: Data
    var width: Int
    var height: Int
    var suggestedName: String
}

/// The app's whole image path. Every byte goes through PluckKit — the app owns no
/// matting logic of its own. Deliberately `nonisolated` and `async` so callers are
/// forced off the main actor.
enum PluckService {
    static let thumbnailMaxEdge = 320
    static let previewMaxEdge = 1200

    private static let engine = VisionEngine()

    static func process(data: Data, name: String) async throws -> ProcessedImage {
        try await process(image: ImageLoader.load(data: data), name: name)
    }

    static func process(url: URL) async throws -> ProcessedImage {
        try await process(
            image: ImageLoader.load(contentsOf: url),
            name: url.deletingPathExtension().lastPathComponent
        )
    }

    static func process(image: CGImage, name: String) async throws -> ProcessedImage {
        let mask = try await engine.mask(for: image)
        let cutout = try Compositor.cutout(image: image, mask: mask)
        let png = try Compositor.pngData(for: cutout)
        let thumb = try Compositor.pngData(for: downsampled(cutout, maxEdge: thumbnailMaxEdge))
        let original = try Compositor.pngData(for: downsampled(image, maxEdge: previewMaxEdge))
        return ProcessedImage(
            pngData: png,
            thumbnailPNG: thumb,
            originalPNG: original,
            width: cutout.width,
            height: cutout.height,
            suggestedName: name.isEmpty ? L.s("Cutout") : name
        )
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Persisting the PNG is what makes a grid cell draggable into other apps:
    /// `NSItemProvider(contentsOf:)` needs a real file, and receivers expect a
    /// sensible filename rather than "image.png".
    static func writeTemporaryFile(_ processed: ProcessedImage, id: UUID) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Pluck", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(processed.suggestedName).appendingPathExtension("png")
        try processed.pngData.write(to: url, options: .atomic)
        return url
    }

    private static func downsampled(_ image: CGImage, maxEdge: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxEdge else { return image }
        let scale = Double(maxEdge) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PluckError.processingFailed(underlying: nil)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else {
            throw PluckError.processingFailed(underlying: nil)
        }
        return scaled
    }
}
