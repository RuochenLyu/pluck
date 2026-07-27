import CoreGraphics
import Foundation
import PluckKit

/// Executes a plan item by item. A failing image never aborts the batch — the caller
/// gets every outcome and derives one exit code from the set.
struct Runner {
    let plan: RunPlan

    func run() async -> [ItemOutcome] {
        guard let engine = EngineCatalog.engine(for: plan.engineID) else {
            return plan.items.map {
                .failure(input: $0.source.display, .modelMissing, "model “\(plan.engineID)” is not installed")
            }
        }

        let showProgress = Terminal.stderrIsTTY && plan.items.count > 1
        var claimed: Set<String> = []
        var outcomes: [ItemOutcome] = []

        for (index, item) in plan.items.enumerated() {
            if showProgress {
                Terminal.note("[\(index + 1)/\(plan.items.count)] \(item.source.display)")
            }

            var collision: ItemOutcome?
            if case .file(let path) = item.destination, !claimed.insert(OutputPlan.identity(of: path)).inserted {
                collision = .failure(
                    input: item.source.display,
                    .outputExists,
                    "\(item.source.display): another input in this run already writes \(path)"
                )
            }

            let outcome = if let collision { collision } else { await process(item: item, engine: engine) }
            outcomes.append(outcome)
            report(outcome)
        }

        return outcomes
    }

    private func process(item: WorkItem, engine: any MattingEngine) async -> ItemOutcome {
        let label = item.source.display
        let started = ContinuousClock.now

        do {
            if case .file(let path) = item.destination, !plan.force,
               FileManager.default.fileExists(atPath: path) {
                return .failure(
                    input: label,
                    .outputExists,
                    "\(label): \(path) already exists; pass --force to overwrite"
                )
            }

            let image: CGImage
            switch item.source {
            case .file(let path): image = try ImageLoader.load(contentsOf: path)
            case .standardInput: image = try ImageLoader.load(data: FileHandle.standardInput.readDataToEndOfFile())
            }

            let mask = try await engine.mask(for: image)
            let composed = try Compositor.compose(image: image, mask: mask, background: plan.background)
            let png = try Compositor.pngData(for: composed)

            switch item.destination {
            case .file(let path):
                try write(png, to: path)
            case .standardOutput:
                Terminal.stdoutData(png)
            }

            let elapsed = ContinuousClock.now - started
            return .success(input: label, ItemSuccess(
                output: item.destination.display,
                width: composed.width,
                height: composed.height,
                durationMs: Self.milliseconds(elapsed)
            ))
        } catch {
            return ItemOutcome(input: label, result: .failure(.from(error, context: label)))
        }
    }

    static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int((Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15).rounded())
    }

    private func write(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    private func report(_ outcome: ItemOutcome) {
        if plan.json {
            Terminal.stdout(JSONReport.line(for: outcome, engine: plan.engineID))
            return
        }
        if let failure = outcome.failure {
            Terminal.error(failure.message)
        }
    }
}
