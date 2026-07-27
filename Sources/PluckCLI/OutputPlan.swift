import Foundation

enum InputSource: Equatable {
    case file(path: String)
    case standardInput

    /// What the JSON `input` field and log lines echo back.
    var display: String {
        switch self {
        case .file(let path): return path
        case .standardInput: return "-"
        }
    }
}

enum Destination: Equatable {
    case file(path: String)
    case standardOutput

    var display: String {
        switch self {
        case .file(let path): return path
        case .standardOutput: return "-"
        }
    }
}

struct WorkItem: Equatable {
    var source: InputSource
    var destination: Destination
}

enum OutputPlan {
    /// Whether `-o` names the file to write rather than the directory to write into.
    ///
    /// `-o` was a directory and nothing else, which made `pluck a.jpg -o out.png` create a
    /// *directory* called `out.png` and exit 0 with the PNG inside it. For a CLI whose
    /// whole point is being driven by something that cannot see the filesystem, a wrong
    /// path that reports success is worse than a refusal.
    ///
    /// An existing directory always wins, so `-o out` keeps working even if something
    /// named `out.png` is what the user meant; otherwise a `.png` suffix means a file.
    static func namesAFile(_ output: String) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: output, isDirectory: &isDirectory), isDirectory.boolValue {
            return false
        }
        return (output as NSString).pathExtension.lowercased() == "png"
    }

    /// `dir/photo.jpg` → `dir/photo.png`; with `-o out/` → `out/photo.png`.
    /// Path math stays on the raw argument strings so relative inputs keep producing
    /// relative outputs in logs and JSON.
    static func destination(forInput input: String, outputDirectory: String?) -> String {
        let name = (input as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let file = (stem.isEmpty ? name : stem) + ".png"
        let directory = outputDirectory ?? (input as NSString).deletingLastPathComponent
        guard !directory.isEmpty else { return file }
        return (directory as NSString).appendingPathComponent(file)
    }

    /// Two inputs can map onto one output (`a/x.jpg b/x.jpg -o out/`). Silently letting the
    /// second clobber the first would be data loss, so collisions fail that item.
    static func identity(of path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
