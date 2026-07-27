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

    private static let pipeline = PluckPipeline()

    static func process(data: Data, name: String) async throws -> ProcessedImage {
        try await process(.data(data), name: name)
    }

    static func process(url: URL) async throws -> ProcessedImage {
        try await process(.file(url), name: PluckSource.file(url).suggestedName ?? "")
    }

    private static func process(_ source: PluckSource, name: String) async throws -> ProcessedImage {
        let run = try await pipeline.run(source)
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
    static func inputThumbnail(data: Data) -> Data? {
        thumbnail(of: try? ImageLoader.load(data: data))
    }

    static func inputThumbnail(of payload: DroppedPayload) -> Data? {
        switch payload {
        case .file(let url): thumbnail(of: try? ImageLoader.load(contentsOf: url))
        case .data(let data): thumbnail(of: try? ImageLoader.load(data: data))
        }
    }

    private static func thumbnail(of image: CGImage?) -> Data? {
        guard let image else { return nil }
        return try? Thumbnail.pngData(for: image, maxEdge: thumbnailMaxEdge)
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `<tmp>/Pluck/` — this app's, exclusively. Neither PluckKit nor the CLI writes here.
    static var temporaryRoot: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Pluck", isDirectory: true)
    }

    /// Persisting the PNG is what makes a grid cell draggable into other apps:
    /// `NSItemProvider(contentsOf:)` needs a real file, and receivers expect a
    /// sensible filename rather than "image.png".
    static func writeTemporaryFile(_ processed: ProcessedImage, id: UUID) throws -> URL {
        let directory = temporaryRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(processed.suggestedName).appendingPathExtension("png")
        try processed.pngData.write(to: url, options: .atomic)
        return url
    }

    /// Everything under `<tmp>/Pluck/` at launch belongs to a run that is already over: the
    /// grid is session-scoped, so nothing on screen can still be pointing at it.
    ///
    /// Quitting drops those files on the floor — Clear deletes the session's, and a crash or
    /// a plain ⌘Q deletes nothing at all. They are cutouts of the user's photos, in the
    /// clear, accumulating for as long as the system leaves the temp directory alone. An app
    /// whose one promise is "your photos stay on this Mac" should not also mean "and pile up
    /// in a directory you were never told about".
    /// `root` is a parameter so the test can point it somewhere harmless: the default is a
    /// directory the developer's own running copy of the app is using.
    static func discardOrphanedTemporaryFiles(at root: URL = temporaryRoot) {
        try? FileManager.default.removeItem(at: root)
    }
}
