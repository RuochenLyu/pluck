import CoreGraphics

/// The single abstraction every background-removal backend implements.
///
/// The returned mask is 8-bit grayscale with the same pixel dimensions as `image`:
/// 255 = fully foreground, 0 = fully background. Multi-subject engines merge all
/// instances into one mask.
public protocol MattingEngine: Sendable {
    /// Stable identifier used by the CLI (`--model`) and the model manifest.
    var id: String { get }

    func mask(for image: CGImage) async throws -> CGImage
}
