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

    /// The stable machine-facing vocabulary. Raw values are a public contract — agents
    /// branch on them in `--json` output — so they change only with a version bump.
    public enum Kind: String, Sendable {
        case noSubject = "no_subject"
        case imageLoadFailed = "image_load_failed"
        case engineUnavailable = "engine_unavailable"
        case modelMissing = "model_missing"
        case processingFailed = "processing_failed"
    }

    public var kind: Kind {
        switch self {
        case .noSubjectDetected: return .noSubject
        case .imageLoadFailed: return .imageLoadFailed
        case .engineUnavailable: return .engineUnavailable
        case .modelMissing: return .modelMissing
        case .processingFailed: return .processingFailed
        }
    }

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
