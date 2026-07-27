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
            return object([
                ("input", .string(outcome.input)),
                ("ok", .bool(false)),
                ("error", .string(failure.kind.slug)),
                ("message", .string(failure.message))
            ])
        }
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
