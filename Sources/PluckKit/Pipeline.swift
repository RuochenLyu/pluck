import CoreGraphics
import Foundation

/// Where the pixels come from. The three cases are the three ways a shell can hand work
/// in: a path (CLI, Finder extension), a pasteboard or network payload (app), and an
/// image the caller already decoded.
public enum PluckSource: Sendable {
    case file(URL)
    case data(Data)
    case image(CGImage)

    /// The input's own name, when it has one — a basename without extension, because
    /// every caller appends its own. Nil for sources that never had a filename; naming
    /// those is a policy decision (`"Cutout"`, `"pasted"`, …) and policy belongs to the
    /// shell, not to the engine.
    public var suggestedName: String? {
        guard case .file(let url) = self else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }
}

/// One run's worth of intermediate state, kept rather than discarded. The CLI only wants
/// `image`, but the app draws a before/after wipe and so needs `input` too, and a future
/// refine-the-edge UI needs `mask` — recomputing any of them means decoding or matting
/// twice.
public struct PluckRun: Sendable {
    /// The decoded input with EXIF orientation applied. Not the caller's bytes: a camera
    /// JPEG's stored pixels are sideways, and this is the upright version the mask and
    /// the composite were computed against.
    public let input: CGImage
    /// 8-bit grayscale at `input`'s dimensions; 255 = foreground.
    public let mask: CGImage
    /// Foreground over the requested background — the thing that gets exported.
    public let image: CGImage

    public var width: Int { image.width }
    public var height: Int { image.height }

    public func pngData() throws -> Data {
        try Compositor.pngData(for: image)
    }
}

/// load → mask → compose, in one call.
///
/// This exists because the four steps are not independently interesting: getting them in
/// the right order with the right intermediate representations is the whole job, and it
/// was previously written out once in the CLI and once in the app — two copies that had
/// already drifted (the app never passed a background through). The Finder extension
/// would have been a third. Shells own I/O, naming, progress and error presentation;
/// everything between the bytes and the composite belongs here.
public struct PluckPipeline: Sendable {
    public var engine: any MattingEngine
    public var background: PluckBackground

    public init(engine: any MattingEngine = VisionEngine(), background: PluckBackground = .transparent) {
        self.engine = engine
        self.background = background
    }

    /// The whole pixel path — decode, matte, compose — runs as one unit inside
    /// `PluckQueue`. Splitting it would be worse than pointless: the intermediate buffers
    /// stay alive across the gaps anyway, so releasing the slot between steps would let
    /// more of them exist at once without any of them finishing sooner.
    public func run(_ source: PluckSource, on queue: PluckQueue = .shared) async throws -> PluckRun {
        let engine = engine
        let background = background
        return try await queue.run {
            let input = try Self.decode(source)
            let mask = try engine.mask(for: input)
            return PluckRun(
                input: input,
                mask: mask,
                image: try Compositor.compose(image: input, mask: mask, background: background)
            )
        }
    }

    private static func decode(_ source: PluckSource) throws -> CGImage {
        switch source {
        case .file(let url): try ImageLoader.load(contentsOf: url)
        case .data(let data): try ImageLoader.load(data: data)
        case .image(let image): image
        }
    }
}
