import CoreGraphics

/// The single abstraction every background-removal backend implements.
///
/// The returned mask is 8-bit grayscale with the same pixel dimensions as `image`:
/// 255 = fully foreground, 0 = fully background. Multi-subject engines merge all
/// instances into one mask.
public protocol MattingEngine: Sendable {
    /// Stable identifier used by the CLI (`--model`) and the model manifest.
    var id: String { get }

    /// Synchronous, and deliberately so. Every backend worth having — Vision's request
    /// handler, `MLModel.prediction` — is a blocking call, and dressing it as `async` only
    /// hid *where* it blocks: on the cooperative pool, one thread per image in flight.
    /// `PluckPipeline` now runs the whole pixel path inside `PluckQueue`, which owns its
    /// threads and limits how many there are, so an engine says what it is and the caller
    /// decides where it runs.
    func mask(for image: CGImage) throws -> CGImage
}
