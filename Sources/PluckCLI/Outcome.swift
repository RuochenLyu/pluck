import Foundation
import PluckKit

/// The stable machine-facing failure vocabulary. Slugs are part of the CLI contract:
/// agents branch on them, so they change only with a version bump.
enum FailureKind: Equatable {
    case noSubject
    case modelMissing
    case engineUnavailable
    case imageLoadFailed
    case outputExists
    case writeFailed
    case processingFailed

    var slug: String {
        switch self {
        case .noSubject: return "no_subject"
        case .modelMissing: return "model_missing"
        case .engineUnavailable: return "engine_unavailable"
        case .imageLoadFailed: return "image_load_failed"
        case .outputExists: return "output_exists"
        case .writeFailed: return "write_failed"
        case .processingFailed: return "processing_failed"
        }
    }
}

struct ItemFailure: Error, Equatable {
    var kind: FailureKind
    var message: String
}

struct ItemSuccess: Equatable {
    var output: String
    var width: Int
    var height: Int
    var durationMs: Int
}

struct ItemOutcome: Equatable {
    var input: String
    var result: Result<ItemSuccess, ItemFailure>

    static func success(input: String, _ value: ItemSuccess) -> ItemOutcome {
        ItemOutcome(input: input, result: .success(value))
    }

    static func failure(input: String, _ kind: FailureKind, _ message: String) -> ItemOutcome {
        ItemOutcome(input: input, result: .failure(ItemFailure(kind: kind, message: message)))
    }

    var failure: ItemFailure? {
        if case .failure(let failure) = result { return failure }
        return nil
    }
}

extension ItemFailure {
    /// PluckKit errors carry no path context; the CLI prefixes it here rather than
    /// widening the library's error type.
    static func from(_ error: any Error, context: String) -> ItemFailure {
        let kind: FailureKind
        switch error {
        case PluckError.noSubjectDetected: kind = .noSubject
        case PluckError.modelMissing: kind = .modelMissing
        case PluckError.engineUnavailable: kind = .engineUnavailable
        case PluckError.imageLoadFailed: kind = .imageLoadFailed
        case is CocoaError: kind = .writeFailed
        default: kind = .processingFailed
        }
        let description = (error as? PluckError)?.errorDescription ?? error.localizedDescription
        return ItemFailure(kind: kind, message: "\(context): \(description)")
    }
}

enum ExitStatus {
    static let success: Int32 = 0
    static let otherError: Int32 = 1
    static let noSubject: Int32 = 2
    static let modelProblem: Int32 = 3

    /// 3 (model) beats 1 (other) beats 2 (no subject): the more actionable the cause,
    /// the higher its precedence, and "no subject" is the only non-error failure.
    static func resolve(_ outcomes: [ItemOutcome]) -> Int32 {
        let kinds = outcomes.compactMap { $0.failure?.kind }
        if kinds.isEmpty { return success }
        if kinds.contains(.modelMissing) { return modelProblem }
        if kinds.contains(where: { $0 != .noSubject }) { return otherError }
        return noSubject
    }
}
