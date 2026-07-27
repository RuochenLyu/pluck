import Foundation

public enum PluckError: Error, LocalizedError, Sendable {
    /// The engine ran successfully but found nothing to cut out.
    case noSubjectDetected
    case imageLoadFailed(reason: String)
    /// The engine cannot run on this machine or OS build (e.g. Vision refusing to
    /// service the request in a VM or on a host without the required compute device).
    case engineUnavailable(reason: String)
    /// Reserved for CoreMLEngine: a model referenced by the manifest is not on disk.
    case modelMissing(id: String)
    case processingFailed(underlying: (any Error)?)

    public var errorDescription: String? {
        switch self {
        case .noSubjectDetected:
            return "No subject was detected in this image."
        case .imageLoadFailed(let reason):
            return "Could not read the image: \(reason)"
        case .engineUnavailable(let reason):
            return "The matting engine is unavailable on this system: \(reason)"
        case .modelMissing(let id):
            return "The model “\(id)” is not installed."
        case .processingFailed(let underlying):
            if let underlying {
                return "Background removal failed: \(underlying.localizedDescription)"
            }
            return "Background removal failed."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noSubjectDetected:
            return "Try an image with a clearer foreground subject, or switch to a higher-quality model."
        case .modelMissing:
            return "Download the model first, then retry."
        default:
            return nil
        }
    }
}
