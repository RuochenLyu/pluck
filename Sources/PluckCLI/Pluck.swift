import ArgumentParser
import Foundation

/// ArgumentParser's own dispatch cannot reach a subcommand past a repeating positional
/// argument (`parseCurrent` swallows every value into `inputs` before the subcommand
/// lookup runs), so the one subcommand group is matched here, before parsing.
@main
enum Entry {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == Models.configuration.commandName {
            Models.main(Array(arguments.dropFirst()))
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
    var model: String = EngineCatalog.defaultEngineID

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
            Terminal.error(error.message)
            throw ExitCode(error.exitCode)
        }

        let outcomes = await Runner(plan: plan).run()
        let status = ExitStatus.resolve(outcomes)
        guard status == ExitStatus.success else { throw ExitCode(status) }
    }
}

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "Inspect and manage matting engines.",
        subcommands: [List.self, Pull.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed engines.")

        @Flag(name: .long, help: "Emit the list as JSON on stdout.")
        var json = false

        func run() throws {
            for engine in EngineCatalog.installed {
                if json {
                    Terminal.stdout(JSONReport.object([
                        ("id", .string(engine.id)),
                        ("summary", .string(engine.summary)),
                        ("builtIn", .bool(engine.builtIn)),
                        ("installed", .bool(true))
                    ]))
                } else {
                    Terminal.stdout("\(engine.id)\t\(engine.builtIn ? "built-in" : "downloaded")\t\(engine.summary)")
                }
            }
        }
    }

    struct Pull: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download a model (not available yet).")

        @Argument(help: ArgumentHelp("Model id.", valueName: "id"))
        var id: String

        func run() throws {
            Terminal.error("cannot pull “\(id)”: downloadable models arrive in v0.3. \(EngineCatalog.availabilityMessage)")
            throw ExitCode(ExitStatus.modelProblem)
        }
    }
}
