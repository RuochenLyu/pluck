import Foundation

/// One NDJSON line per image. Field order is part of the contract for humans reading
/// logs, and `JSONEncoder` does not preserve declaration order — hence the hand-rolled
/// ordered writer.
enum JSONReport {
    static func line(for outcome: ItemOutcome, engine: String) -> String {
        switch outcome.result {
        case .success(let value):
            return object([
                ("input", .string(outcome.input)),
                ("output", .string(value.output)),
                ("width", .number(value.width)),
                ("height", .number(value.height)),
                ("durationMs", .number(value.durationMs)),
                ("engine", .string(engine)),
                ("ok", .bool(true))
            ])
        case .failure(let failure):
            // Same shape as the success record, minus what does not exist yet. A caller
            // that let the CLI derive output paths needs `output` most on the records
            // where nothing was written, and `engine` is what tells it whether retrying
            // with a different `--model` is worth trying at all.
            var fields: [(String, Value)] = [("input", .string(outcome.input))]
            if let output = outcome.output { fields.append(("output", .string(output))) }
            fields.append(("error", .string(failure.kind.slug)))
            fields.append(("message", .string(failure.message)))
            fields.append(("engine", .string(engine)))
            fields.append(("ok", .bool(false)))
            return object(fields)
        }
    }

    /// The run as a whole failing before it had any items — a bad argument, a model that
    /// is not there. Without this, `--json` printed nothing at all on stdout and left an
    /// exit code and a line of English prose on stderr as the only evidence.
    static func line(for error: SetupError) -> String {
        object([
            ("error", .string(error.slug)),
            ("message", .string(error.message)),
            ("ok", .bool(false))
        ])
    }

    enum Value {
        case string(String)
        case number(Int)
        case bool(Bool)

        var encoded: String {
            switch self {
            case .string(let text): return JSONReport.quote(text)
            case .number(let value): return String(value)
            case .bool(let value): return value ? "true" : "false"
            }
        }
    }

    static func object(_ fields: [(String, Value)]) -> String {
        let body = fields.map { "\(quote($0.0)):\($0.1.encoded)" }.joined(separator: ",")
        return "{\(body)}"
    }

    /// Minimal RFC 8259 string escaping. Slashes stay unescaped so paths read naturally.
    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
