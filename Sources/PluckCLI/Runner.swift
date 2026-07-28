import CoreGraphics
import Foundation
import PluckKit

/// Executes a plan. A failing image never aborts the batch — the caller gets every
/// outcome and derives one exit code from the set.
struct Runner: Sendable {
    let plan: RunPlan

    func run() async -> [ItemOutcome] {
        let engine: any MattingEngine
        do {
            // Core ML compiles a freshly downloaded package on first use, which takes
            // 5–10 seconds; say so rather than looking hung, but only to a human.
            if Terminal.stderrIsTTY, plan.engineID != Engines.defaultEngineID {
                Terminal.note("loading \(plan.engineID)…")
            }
            engine = try await Engines.catalog.engine(for: plan.engineID)
        } catch {
            let failure = ItemFailure.from(error, context: plan.engineID)
            let outcomes = plan.items.map {
                ItemOutcome(input: $0.source.display, output: $0.destination.display, result: .failure(failure))
            }
            outcomes.forEach(report)
            return outcomes
        }

        let pipeline = PluckPipeline(engine: engine, background: plan.background)
        let prepared = claimDestinations()

        // The queue in PluckKit is what bounds memory and CPU width; running the items
        // one await at a time meant that bound was never reached, and a folder of forty
        // photographs took forty times one photograph.
        var outcomes = [ItemOutcome?](repeating: nil, count: prepared.count)
        var reported = 0
        await withTaskGroup(of: (Int, ItemOutcome).self) { group in
            for (index, item) in prepared.enumerated() {
                group.addTask {
                    if let collision = item.collision { return (index, collision) }
                    return (index, await process(item: item.work, through: pipeline))
                }
            }
            for await (index, outcome) in group {
                outcomes[index] = outcome
                // Records are held back until every earlier one has been emitted: the
                // output order is the order the inputs were given in, whatever order the
                // work finished in. An agent reading NDJSON pairs records with arguments
                // positionally, and `[3/8]` arriving before `[1/8]` is just noise.
                while reported < outcomes.count, let ready = outcomes[reported] {
                    announce(ready, index: reported, of: prepared.count)
                    report(ready)
                    reported += 1
                }
            }
        }
        return outcomes.compactMap { $0 }
    }

    private struct PreparedItem {
        var work: WorkItem
        /// Set when an earlier item in this run already owns the destination.
        var collision: ItemOutcome?
    }

    /// Two inputs can map onto one output (`a/x.jpg b/x.jpg -o out/`). Silently letting
    /// the second clobber the first would be data loss, so collisions fail that item —
    /// decided here, in input order, before anything runs concurrently.
    private func claimDestinations() -> [PreparedItem] {
        var claimed: [String: (input: String, output: String)] = [:]
        return plan.items.map { item in
            guard case .file(let path) = item.destination else {
                return PreparedItem(work: item, collision: nil)
            }
            guard let owner = claimed[path.identity] else {
                claimed[path.identity] = (item.source.display, path.display)
                return PreparedItem(work: item, collision: nil)
            }
            // Naming the owner's spelling of the path matters: on a case-insensitive
            // volume the two destinations are the same file under different names, and
            // repeating this item's own name would explain nothing.
            return PreparedItem(work: item, collision: .failure(
                input: item.source.display,
                output: item.destination.display,
                .outputExists,
                "\(item.source.display): \(path.display) is the same file as \(owner.output), already written by \(owner.input)"
            ))
        }
    }

    private func process(item: WorkItem, through pipeline: PluckPipeline) async -> ItemOutcome {
        let label = item.source.display
        let started = ContinuousClock.now

        do {
            if case .file(let path) = item.destination, !plan.force,
               FileManager.default.fileExists(atPath: path.url.path) {
                return .failure(
                    input: label,
                    output: item.destination.display,
                    .outputExists,
                    "\(label): \(path.display) already exists; pass --force to overwrite"
                )
            }

            let source: PluckSource
            switch item.source {
            case .file(let path):
                source = .file(path.url)
            case .standardInput:
                // Read here rather than letting the pipeline take a file handle: draining
                // stdin is a one-shot side effect, and a retry that silently produced an
                // empty image would be worse than the error.
                let data = FileHandle.standardInput.readDataToEndOfFile()
                guard !data.isEmpty else { throw PluckError.imageLoadFailed(reason: "no data on stdin") }
                source = .data(data)
            }

            let run = try await pipeline.run(source)
            let png = try run.pngData()

            switch item.destination {
            case .file(let path):
                try write(png, to: path.url)
            case .standardOutput:
                Terminal.stdoutData(png)
            }

            let elapsed = ContinuousClock.now - started
            return .success(input: label, ItemSuccess(
                output: item.destination.display,
                width: run.width,
                height: run.height,
                durationMs: Self.milliseconds(elapsed)
            ))
        } catch {
            return ItemOutcome(
                input: label,
                output: item.destination.display,
                result: .failure(.from(error, context: label))
            )
        }
    }

    static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int((Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15).rounded())
    }

    private func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    private func announce(_ outcome: ItemOutcome, index: Int, of total: Int) {
        guard Terminal.stderrIsTTY, total > 1 else { return }
        Terminal.note("[\(index + 1)/\(total)] \(outcome.input)")
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
