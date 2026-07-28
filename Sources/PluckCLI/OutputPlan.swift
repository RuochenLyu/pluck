import Foundation

/// A path argument as the user wrote it, and the one filesystem location it means.
///
/// The two spellings used to live in different places and disagree. The overwrite check
/// called `FileManager.fileExists(atPath:)`, which takes the string literally; the write
/// called `URL(fileURLWithPath:)`, which expands a leading `~`. So `-o '~/hero.png'`
/// checked a path that never exists, found nothing in the way, and overwrote a completely
/// different file — reporting success. Resolution happens once, here, and no code
/// downstream is allowed to see the raw string again.
struct ResolvedPath: Equatable, Sendable {
    /// As typed. Logs and JSON echo this back, so paths read the way they were written.
    let display: String
    /// Tilde-expanded, standardized. The only thing that touches disk.
    let url: URL

    init(_ path: String) {
        display = path
        url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    /// Which outputs count as the same file within one run.
    ///
    /// Case-folded unconditionally. The volume macOS ships by default is case-insensitive,
    /// where `X.png` and `x.png` are one file — two `ok` records and one surviving file is
    /// data loss, and the caller has no way to notice. On a case-sensitive volume this
    /// refuses a run that would have worked; that is the half of the trade you can survive.
    var identity: String { url.path.lowercased() }
}

enum InputSource: Equatable, Sendable {
    case file(ResolvedPath)
    case standardInput

    static func file(path: String) -> InputSource { .file(ResolvedPath(path)) }

    /// What the JSON `input` field and log lines echo back.
    var display: String {
        switch self {
        case .file(let path): return path.display
        case .standardInput: return "-"
        }
    }
}

enum Destination: Equatable, Sendable {
    case file(ResolvedPath)
    case standardOutput

    static func file(path: String) -> Destination { .file(ResolvedPath(path)) }

    var display: String {
        switch self {
        case .file(let path): return path.display
        case .standardOutput: return "-"
        }
    }
}

struct WorkItem: Equatable, Sendable {
    var source: InputSource
    var destination: Destination
}

enum OutputPlan {
    /// What a `-o` argument is asking for.
    enum Kind: Equatable {
        case file
        case directory
        /// Nothing the user can have meant. Better than picking one of the readings.
        case malformed(reason: String)
    }

    /// `-o` was read as a directory and nothing else, which made `pluck a.jpg -o out.png`
    /// create a *directory* called `out.png` and exit 0 with the PNG inside it. For a CLI
    /// whose whole point is being driven by something that cannot see the filesystem, a
    /// wrong path that reports success is worse than a refusal.
    ///
    /// An existing directory always wins, so `-o out` keeps working even if something
    /// named `out.png` is what the user meant; otherwise a `.png` suffix means a file.
    static func classify(_ output: String) -> Kind {
        var isDirectory: ObjCBool = false
        let resolved = ResolvedPath(output)
        if FileManager.default.fileExists(atPath: resolved.url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return .directory
        }

        // A trailing slash is how every shell spells "directory", and it survives
        // `pathExtension` intact — `-o out.png/` was being read as a filename.
        if output.hasSuffix("/") { return .directory }

        let name = (output as NSString).lastPathComponent
        if name.hasPrefix("."), name != ".", name != "..", (name as NSString).pathExtension.isEmpty {
            // `-o .png` has no stem, so `pathExtension` is empty and the whole thing reads
            // as a directory name — one that is also invisible in Finder. Nobody means that.
            return .malformed(reason: """
                --output “\(output)” names a hidden file, not a .png file or a directory. \
                Write “dir/name.png” for a file, or “\(output)/” if you really meant a directory.
                """)
        }

        return (output as NSString).pathExtension.lowercased() == "png" ? .file : .directory
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
}
