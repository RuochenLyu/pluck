import Foundation

/// Every human-readable byte goes to stderr; stdout carries only payload
/// (NDJSON records, or the PNG itself in stdin/stdout mode).
enum Terminal {
    static var stderrIsTTY: Bool { isatty(STDERR_FILENO) == 1 }

    static func note(_ message: String) {
        write(message + "\n", to: FileHandle.standardError)
    }

    static func error(_ message: String) {
        write("pluck: " + message + "\n", to: FileHandle.standardError)
    }

    static func stdout(_ line: String) {
        write(line + "\n", to: FileHandle.standardOutput)
    }

    static func stdoutData(_ data: Data) {
        FileHandle.standardOutput.write(data)
    }

    private static func write(_ string: String, to handle: FileHandle) {
        handle.write(Data(string.utf8))
    }
}
