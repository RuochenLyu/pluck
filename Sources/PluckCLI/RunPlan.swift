import Foundation
import PluckKit

/// A refusal that happens before any item exists, so it has no `input` to be reported
/// against — the run itself is what failed.
struct SetupError: Error, Equatable {
    var message: String
    var exitCode: Int32
    /// The machine-facing name for this refusal. Same vocabulary as the per-item `error`
    /// field: an agent branching on `model_missing` should not have to care whether the
    /// model went missing before the run or during it.
    var slug: String = SetupError.badArguments

    static let badArguments = "bad_arguments"
    static let modelMissing = PluckError.Kind.modelMissing.rawValue
}

/// Everything the run needs, resolved and validated before a single pixel is touched.
struct RunPlan: Equatable, Sendable {
    var items: [WorkItem]
    var engineID: String
    var background: PluckBackground
    var force: Bool
    var json: Bool

    var writesImageToStandardOutput: Bool {
        items.contains { $0.destination == .standardOutput }
    }

    static func make(
        inputs: [String],
        outputDirectory: String?,
        force: Bool,
        model: String,
        background: String?,
        json: Bool
    ) throws -> RunPlan {
        guard !inputs.isEmpty else {
            throw SetupError(message: "no input files. Usage: pluck <image>... [-o <dir>]", exitCode: 1)
        }

        switch Engines.catalog.descriptor(for: model) {
        case .some(let descriptor) where descriptor.installed:
            break
        case .some:
            throw SetupError(
                message: "model “\(model)” is not installed. Run: pluck models pull \(model)",
                exitCode: 3,
                slug: SetupError.modelMissing
            )
        case .none:
            throw SetupError(
                message: "unknown model “\(model)”. \(Engines.catalog.availabilityMessage)",
                exitCode: 3,
                slug: SetupError.modelMissing
            )
        }

        let composited: PluckBackground
        if let background {
            guard let color = HexColor.parse(background) else {
                throw SetupError(
                    message: "invalid --background “\(background)”. Expected a hex color such as #ffffff",
                    exitCode: 1
                )
            }
            composited = .solid(color)
        } else {
            composited = .transparent
        }

        let usesStdin = inputs.contains("-")
        if usesStdin {
            guard inputs.count == 1 else {
                throw SetupError(message: "- cannot be combined with other inputs", exitCode: 1)
            }
            guard outputDirectory == nil else {
                throw SetupError(message: "- writes the PNG to stdout; --output is not applicable", exitCode: 1)
            }
            // The PNG owns stdout in this mode, so NDJSON has nowhere to go.
            guard !json else {
                throw SetupError(message: "--json cannot be combined with writing the image to stdout", exitCode: 1)
            }
            return RunPlan(
                items: [WorkItem(source: .standardInput, destination: .standardOutput)],
                engineID: model,
                background: composited,
                force: force,
                json: json
            )
        }

        if let output = outputDirectory {
            switch OutputPlan.classify(output) {
            case .malformed(let reason):
                throw SetupError(message: reason, exitCode: 1)
            case .file:
                guard inputs.count == 1 else {
                    throw SetupError(
                        message: "--output “\(output)” names a single file, but \(inputs.count) inputs were given. Pass a directory instead.",
                        exitCode: 1
                    )
                }
                return RunPlan(
                    items: [WorkItem(source: .file(path: inputs[0]), destination: .file(path: output))],
                    engineID: model,
                    background: composited,
                    force: force,
                    json: json
                )
            case .directory:
                break
            }
        }

        let items = inputs.map { input in
            WorkItem(
                source: .file(path: input),
                destination: .file(path: OutputPlan.destination(forInput: input, outputDirectory: outputDirectory))
            )
        }
        return RunPlan(
            items: items,
            engineID: model,
            background: composited,
            force: force,
            json: json
        )
    }
}
