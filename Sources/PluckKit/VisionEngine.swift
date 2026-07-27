import CoreGraphics
import Foundation
import Vision

/// Default engine: the system foreground-instance segmentation model (macOS 14+),
/// the same one behind Finder's "Remove Background". Zero download, zero bundle size.
public struct VisionEngine: MattingEngine {
    public let id = "vision"

    public init() {}

    public func mask(for image: CGImage) async throws -> CGImage {
        guard image.width > 0, image.height > 0 else {
            throw PluckError.imageLoadFailed(reason: "image has zero width or height")
        }

        let input = try ImageBuffers.downsampled(image) ?? image
        let raw = try Self.foregroundMask(for: input)
        return try ImageBuffers.resizeMask(raw, width: image.width, height: image.height)
    }

    private static func foregroundMask(for image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw classify(error)
        }

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw PluckError.noSubjectDetected
        }

        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
        } catch {
            throw classify(error)
        }

        let mask = try ImageBuffers.grayscale(from: buffer)
        guard try !isEmpty(mask) else { throw PluckError.noSubjectDetected }
        return mask
    }

    /// Vision occasionally reports an instance whose mask is all background; treat that
    /// as "nothing found" rather than handing callers a fully transparent cutout.
    private static func isEmpty(_ mask: CGImage) throws -> Bool {
        let gray = try ImageBuffers.grayscale(from: mask)
        return !gray.pixels.contains { $0 > 8 }
    }

    /// Vision reports "cannot run here" (no supported compute device, headless VM,
    /// espresso/ANE failures) through generic internal-error codes; those are an
    /// environment problem, not a problem with the user's image.
    private static func classify(_ error: any Error) -> PluckError {
        let nsError = error as NSError
        guard nsError.domain == VNErrorDomain || nsError.domain == "com.apple.Vision" else {
            return .processingFailed(underlying: error)
        }
        let unavailable: Set<Int> = [
            VNErrorCode.notImplemented.rawValue,
            VNErrorCode.internalError.rawValue,
            VNErrorCode.dataUnavailable.rawValue,
            VNErrorCode.unsupportedRequest.rawValue,
            VNErrorCode.unsupportedRevision.rawValue,
            VNErrorCode.unsupportedComputeStage.rawValue,
            VNErrorCode.unsupportedComputeDevice.rawValue
        ]
        if unavailable.contains(nsError.code) {
            return .engineUnavailable(reason: nsError.localizedDescription)
        }
        return .processingFailed(underlying: error)
    }
}
