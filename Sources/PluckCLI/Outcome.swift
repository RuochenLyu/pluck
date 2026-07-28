import Foundation
import PluckKit

/// The stable machine-facing failure vocabulary. Slugs are part of the CLI contract:
/// agents branch on them, so they change only with a version bump. Everything the engine
/// itself can fail at lives in `PluckError.Kind`; only the two file-handling failures
/// below are the CLI's own, because they happen around the engine, never inside it.
enum FailureKind: Equatable {
    case library(PluckError.Kind)
    case outputExists
    case writeFailed

    static let noSubject = FailureKind.library(.noSubject)
    static let modelMissing = FailureKind.library(.modelMissing)
    static let modelLoadFailed = FailureKind.library(.modelLoadFailed)
    static let engineUnavailable = FailureKind.library(.engineUnavailable)
    static let imageLoadFailed = FailureKind.library(.imageLoadFailed)
    static let processingFailed = FailureKind.library(.processingFailed)

    var slug: String {
        switch self {
        case .library(let kind): return kind.rawValue
        case .outputExists: return "output_exists"
        case .writeFailed: return "write_failed"
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
        case let error as PluckError: kind = .library(error.kind)
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
        // A model that is absent and a model that will not load are the same problem to
        // whoever is scripting this: the model is not usable, exit 3 says so.
        if kinds.contains(.modelMissing) || kinds.contains(.modelLoadFailed) { return modelProblem }
        if kinds.contains(where: { $0 != .noSubject }) { return otherError }
        return noSubject
    }
}
