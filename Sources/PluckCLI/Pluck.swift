import ArgumentParser
import Foundation
import PluckKit

/// ArgumentParser's own dispatch cannot reach a subcommand past a repeating positional
/// argument (`parseCurrent` swallows every value into `inputs` before the subcommand
/// lookup runs), so the one subcommand group is matched here, before parsing.
@main
enum Entry {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == Models.configuration.commandName {
            await Models.main(Array(arguments.dropFirst()))
            return
        }
        await Pluck.main(arguments)
    }
}

struct Pluck: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pluck",
        abstract: "Lift subjects out of photos. Offline, free, open source.",
        discussion: """
            pluck photo.jpg                 write photo.png next to the input
            pluck *.jpg -o out/             batch into a directory
            cat photo.jpg | pluck - > cut.png
            pluck photo.jpg --json          one NDJSON record per image on stdout

            Exit codes: 0 success, 2 no subject detected, 3 model missing or unknown, 1 other errors.
            """,
        version: "0.1.0-dev",
        subcommands: [Models.self]
    )

    @Argument(help: ArgumentHelp("Image files, or - to read a single image from stdin.", valueName: "input"))
    var inputs: [String] = []

    @Option(
        name: [.customShort("o"), .customLong("output")],
        help: ArgumentHelp(
            "Directory for the results, created if missing; or a single .png path when there is one input.",
            valueName: "dir|file.png"
        )
    )
    var output: String?

    @Flag(name: .long, help: "Overwrite existing output files.")
    var force = false

    @Option(name: .long, help: ArgumentHelp("Matting engine id.", valueName: "id"))
    var model: String = Engines.defaultEngineID

    @Option(
        name: .long,
        help: ArgumentHelp("Composite onto a solid background, e.g. #ffffff. Default: transparent.", valueName: "hex")
    )
    var background: String?

    @Flag(name: .long, help: "Emit one JSON record per image on stdout (NDJSON).")
    var json = false

    func run() async throws {
        let plan: RunPlan
        do {
            plan = try RunPlan.make(
                inputs: inputs,
                outputDirectory: output,
                force: force,
                model: model,
                background: background,
                json: json
            )
        } catch let error as SetupError {
            // stdout is the only channel an agent is required to read, and `--json` is it
            // asking for one. A run that dies before it has items still owes it a record.
            if json { Terminal.stdout(JSONReport.line(for: error)) }
            Terminal.error(error.message)
            throw ExitCode(error.exitCode)
        }

        let outcomes = await Runner(plan: plan).run()
        let status = ExitStatus.resolve(outcomes)
        guard status == ExitStatus.success else { throw ExitCode(status) }
    }
}

struct Models: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "Inspect and manage matting engines.",
        subcommands: [List.self, Pull.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List the engines this machine can use, and the ones it could download."
        )

        @Flag(name: .long, help: "Emit the list as JSON on stdout.")
        var json = false

        func run() throws {
            for engine in Engines.catalog.all {
                if json {
                    Terminal.stdout(JSONReport.object([
                        ("id", .string(engine.id)),
                        ("summary", .string(engine.summary)),
                        ("builtIn", .bool(engine.builtIn)),
                        ("installed", .bool(engine.installed))
                    ]))
                } else {
                    let state = engine.builtIn ? "built-in" : (engine.installed ? "installed" : "available")
                    Terminal.stdout("\(engine.id)\t\(state)\t\(engine.summary)")
                }
            }
        }
    }

    struct Pull: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download and install a model.")

        @Argument(help: ArgumentHelp("Model id.", valueName: "id"))
        var id: String

        @Flag(name: .long, help: "Download again even if the model is already installed.")
        var force = false

        func run() async throws {
            guard let registry = Engines.catalog.registry, let model = registry.descriptor(for: id) else {
                Terminal.error("unknown model “\(id)”. \(Engines.catalog.availabilityMessage)")
                throw ExitCode(ExitStatus.modelProblem)
            }
            if !force, let installed = registry.localURL(for: id) {
                Terminal.note("\(id) is already installed at \(installed.path)")
                return
            }

            Terminal.note("\(id): \(model.displayName), \(Self.megabytes(model.bytes)) — \(model.license), \(model.source.absoluteString)")
            let reporter = ProgressReporter()
            do {
                let url = try await registry.install(id, force: force) { progress in
                    reporter.report(progress)
                }
                reporter.finish()
                Terminal.note("installed \(id) at \(url.path)")
            } catch {
                reporter.finish()
                let description = (error as? PluckError)?.errorDescription ?? error.localizedDescription
                Terminal.error(description)
                throw ExitCode(ExitStatus.modelProblem)
            }
        }

        static func megabytes(_ bytes: Int64) -> String {
            String(format: "%.0f MB", Double(bytes) / 1_000_000)
        }
    }
}

/// Redraws one line on stderr while the bytes come down. Silent without a TTY: a progress
/// bar in a log file is noise, and the CLI's contract is that stderr stays quiet for agents.
private final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPercent = -1
    private var drew = false

    func report(_ progress: ModelRegistry.Progress) {
        guard Terminal.stderrIsTTY else { return }
        lock.lock()
        defer { lock.unlock() }

        let label: String
        switch progress.phase {
        case .downloading:
            let percent = Int((progress.fraction ?? 0) * 100)
            guard percent != lastPercent else { return }
            lastPercent = percent
            label = "downloading \(percent)%"
        case .verifying:
            label = "verifying…"
        case .installing:
            label = "installing…"
        }
        FileHandle.standardError.write(Data("\r\u{1B}[K\(label)".utf8))
        drew = true
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard drew else { return }
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
        drew = false
    }
}
