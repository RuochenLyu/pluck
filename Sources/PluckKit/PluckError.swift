import Foundation

public enum PluckError: Error, LocalizedError, Sendable {
    /// The engine ran successfully but found nothing to cut out.
    case noSubjectDetected
    case imageLoadFailed(reason: String)
    /// The engine cannot run on this machine or OS build (e.g. Vision refusing to
    /// service the request in a VM or on a host without the required compute device).
    case engineUnavailable(reason: String)
    /// A model referenced by the manifest is not on disk.
    case modelMissing(id: String)
    /// The model is on disk but Core ML would not compile or load it.
    case modelLoadFailed(id: String, reason: String)
    /// Fetching or verifying a model failed: transport, HTTP status, SHA256 mismatch,
    /// unusable archive. All of them leave nothing installed.
    case modelDownloadFailed(id: String, reason: String)
    case manifestInvalid(reason: String)
    case processingFailed(underlying: (any Error)?)

    /// The stable machine-facing vocabulary. Raw values are a public contract — agents
    /// branch on them in `--json` output — so they change only with a version bump.
    public enum Kind: String, Sendable {
        case noSubject = "no_subject"
        case imageLoadFailed = "image_load_failed"
        case engineUnavailable = "engine_unavailable"
        case modelMissing = "model_missing"
        case modelLoadFailed = "model_load_failed"
        case modelDownloadFailed = "model_download_failed"
        case manifestInvalid = "manifest_invalid"
        case processingFailed = "processing_failed"
    }

    public var kind: Kind {
        switch self {
        case .noSubjectDetected: return .noSubject
        case .imageLoadFailed: return .imageLoadFailed
        case .engineUnavailable: return .engineUnavailable
        case .modelMissing: return .modelMissing
        case .modelLoadFailed: return .modelLoadFailed
        case .modelDownloadFailed: return .modelDownloadFailed
        case .manifestInvalid: return .manifestInvalid
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
        case .modelLoadFailed(let id, let reason):
            return "The model “\(id)” could not be loaded: \(reason)"
        case .modelDownloadFailed(let id, let reason):
            return "Downloading the model “\(id)” failed: \(reason)"
        case .manifestInvalid(let reason):
            return "The model manifest is unusable: \(reason)"
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
        case .modelLoadFailed, .modelDownloadFailed:
            return "Download the model again; the copy on disk is unusable."
        default:
            return nil
        }
    }
}
