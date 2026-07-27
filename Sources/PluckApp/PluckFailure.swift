import Foundation
import PluckKit

/// Why a job failed, in the app's own words.
///
/// PluckKit stays machine-facing: `PluckError.Kind` is a stable vocabulary agents branch on
/// in `--json`, and `errorDescription` is English developer copy the CLI prints. Giving the
/// library a localization path would cost a second String Catalog to compile into the
/// bundle and a second `Bundle` to resolve — to produce copy written by the layer that
/// knows the least about who is reading it. So the library names the failure and the app
/// decides what to say about it (decisions.md 2026-07-27).
enum PluckFailure: Equatable, Sendable {
    /// Nothing usable was offered at all — an empty clipboard, or a drop carrying no image.
    /// Distinct from `unreadable`: there is nothing to blame the picture for.
    case noInput
    case noSubject
    case unreadable
    case engineUnavailable
    case unknown

    init(_ error: any Error) {
        guard let error = error as? PluckError else {
            self = .unknown
            return
        }
        switch error.kind {
        case .noSubject:
            self = .noSubject
        case .imageLoadFailed:
            self = .unreadable
        case .engineUnavailable:
            self = .engineUnavailable
        case .modelMissing:
            // v0.3 (CoreMLEngine) needs its own copy here, with a download affordance
            // beside it. Until that exists, "download the model first" would point at a
            // button that does not.
            self = .unknown
        case .processingFailed:
            self = .unknown
        }
    }

    /// One sentence, no error codes, and it names the thing the user can do differently
    /// where there is one. This is the only place a v0.1 failure gets explained.
    var message: String {
        switch self {
        case .noInput: L.s("No image found — copy or drop a picture first.")
        case .noSubject: L.s("No subject found in this image.")
        case .unreadable: L.s("That file isn’t an image Pluck can read.")
        case .engineUnavailable: L.s("Background removal isn’t available on this Mac.")
        case .unknown: L.s("Something went wrong plucking this image.")
        }
    }
}

/// The end of one job. `failure` carries its reason rather than the caller re-deriving it:
/// the reason is decided where the error is caught, and every later hop that re-guesses is
/// a place the message can drift from what actually happened.
enum PluckOutcome: Equatable, Sendable {
    case success
    /// Abandoned before the engine ran, because the grid already holds exactly this cutout.
    /// Not a failure and not a result: nothing was produced, and nothing went wrong.
    case superseded
    case failure(PluckFailure)

    var failureReason: PluckFailure? {
        guard case .failure(let reason) = self else { return nil }
        return reason
    }
}
