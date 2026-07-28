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

/// The app's whole image path. Nothing here decodes, mattes or composites: that is
/// `PluckPipeline`'s job, and this type is the shell that turns one run into the several
/// encodings the UI needs. Deliberately `nonisolated` and `async` so callers are forced
/// off the main actor.
enum PluckService {
    static let thumbnailMaxEdge = 320
    static let previewMaxEdge = 1200

    /// Deliberately *not* `PluckQueue.shared`. Placeholder thumbnails are the batch list's
    /// only "yes, I got that file" for as long as matting takes, so queueing them behind
    /// forty mattings would leave forty blank rows for a minute. Their own narrow queue
    /// keeps them off the cooperative pool without letting them starve the real work.
    private static let decoding = PluckQueue(width: 2, label: "com.aix4u.pluck.thumbnails")

    /// The engine is passed in rather than read from preferences here: resolving it can
    /// mean a ten-second Core ML compile, which the caller has to be able to say something
    /// about before the wait starts (`AppModel.engine(for:)`).
    static func process(
        data: Data,
        name: String,
        engine: any MattingEngine = VisionEngine()
    ) async throws -> ProcessedImage {
        try await process(.data(data), name: name, engine: engine)
    }

    static func process(url: URL, engine: any MattingEngine = VisionEngine()) async throws -> ProcessedImage {
        try await process(.file(url), name: PluckSource.file(url).suggestedName ?? "", engine: engine)
    }

    private static func process(
        _ source: PluckSource,
        name: String,
        engine: any MattingEngine
    ) async throws -> ProcessedImage {
        let run = try await PluckPipeline(engine: engine).run(source)
        return ProcessedImage(
            pngData: try run.pngData(),
            thumbnailPNG: try Thumbnail.pngData(for: run.image, maxEdge: thumbnailMaxEdge),
            originalPNG: try Thumbnail.pngData(for: run.input, maxEdge: previewMaxEdge),
            width: run.width,
            height: run.height,
            suggestedName: name.isEmpty ? L.s("Cutout") : name
        )
    }

    /// The *input* image at grid-thumbnail size, for the placeholder card that stands in
    /// while matting runs (decisions.md 2026-07-27). Returns nil rather than throwing:
    /// a placeholder that cannot be drawn is a cosmetic loss, and the real decode error
    /// surfaces from `process` a moment later. Costs one extra decode of the source —
    /// paid deliberately, so the grid can show *which* picture is being worked on.
    static func inputThumbnail(data: Data) async -> Data? {
        await thumbnail { try ImageLoader.load(data: data) }
    }

    static func inputThumbnail(of payload: DroppedPayload) async -> Data? {
        switch payload {
        case .file(let url): await thumbnail { try ImageLoader.load(contentsOf: url) }
        case .data(let data): await thumbnail { try ImageLoader.load(data: data) }
        }
    }

    private static func thumbnail(_ decode: @escaping @Sendable () throws -> CGImage) async -> Data? {
        try? await decoding.run { try Thumbnail.pngData(for: decode(), maxEdge: thumbnailMaxEdge) }
    }

    /// Re-encodes stored PNG bytes down to what a view can actually show. Alpha survives
    /// the round trip — `Thumbnail` goes through the same RGBA path the cutouts themselves
    /// are written with — and nil comes back for bytes that will not decode, which the
    /// caller already has to handle for a file that has gone missing.
    ///
    /// Returns `Data` rather than a `CGImage` for the same reason `ProcessedImage` does:
    /// it crosses an isolation boundary, and PNG bytes are the app's lingua franca for that.
    static func fitted(_ data: Data?, maxEdge: Int) -> Data? {
        guard let data else { return nil }
        return try? Thumbnail.pngData(for: ImageLoader.load(data: data), maxEdge: maxEdge)
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

}
