import Foundation

/// Where a finished cutout's bytes live — on disk, in exactly one copy.
///
/// Until now an entry carried three `Data` blobs in memory: the export, the preview's
/// "before" half, and the grid thumbnail, plus a fourth copy of the export written to
/// `/tmp` so the cell could be dragged out. Twelve of those is affordable for one session
/// and not affordable for a history that survives a quit. So the file *is* the entry: only
/// the thumbnail stays resident, and the rest is read back when something asks for it.
///
/// Two roots, chosen by the user's history preference:
/// - `session` — `<tmp>/Pluck/`, swept at launch, so "don't remember" really means the
///   files die with the session.
/// - `history` — `~/Library/Application Support/Pluck/History/`, plus an `index.json`
///   that says what order they were in and what they were called.
struct CutoutArchive: Sendable {
    let root: URL
    /// Whether this root keeps an index. Without one, a restart finds a directory of
    /// anonymous UUIDs and no reason to trust any of it — which is the point for `/tmp`.
    let keepsIndex: Bool

    static let session = CutoutArchive(
        root: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Pluck", isDirectory: true),
        keepsIndex: false
    )

    static let history = CutoutArchive(root: Self.historyRoot, keepsIndex: true)

    private static var historyRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Pluck/History", isDirectory: true)
    }

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    // MARK: - Writing

    /// Lays one cutout down as a directory of three files and returns the entry that points
    /// at them. The cutout keeps the picture's own name because that name shows up in
    /// Finder the moment the cell is dragged out; the other two are fixed names, since
    /// nothing user-facing ever sees them.
    func store(_ processed: ProcessedImage, id: UUID) throws -> RecentItem {
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(processed.suggestedName).appendingPathExtension("png")
        let original = directory.appendingPathComponent("original.png")
        let thumbnail = directory.appendingPathComponent("thumbnail.png")
        try processed.pngData.write(to: file, options: .atomic)
        try processed.originalPNG.write(to: original, options: .atomic)
        try processed.thumbnailPNG.write(to: thumbnail, options: .atomic)
        return RecentItem(
            id: id,
            fingerprint: PluckService.fingerprint(processed.pngData),
            thumbnailPNG: processed.thumbnailPNG,
            fileURL: file,
            originalURL: original,
            suggestedName: processed.suggestedName,
            pixelWidth: processed.width,
            pixelHeight: processed.height
        )
    }

    /// Records the order and the names. Entries that live under a different root are
    /// skipped rather than being recorded as missing files: flipping the preference
    /// mid-session leaves both kinds in the same grid, and only ours is ours to remember.
    func writeIndex(_ items: [RecentItem]) {
        guard keepsIndex else { return }
        let records = items.filter { contains($0) }.map(Record.init)
        guard !records.isEmpty else {
            try? FileManager.default.removeItem(at: indexURL)
            return
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Index(items: records)) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Reading

    /// The index is the truth about order; the directory is the truth about what exists.
    /// Where they disagree the directory wins — a record whose PNG is gone is dropped, and
    /// a directory no surviving record points at is deleted, which is how a crash between
    /// `store` and `writeIndex` cleans up after itself.
    func load(limit: Int) -> [RecentItem] {
        guard keepsIndex else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let index = (try? Data(contentsOf: indexURL)).flatMap { try? decoder.decode(Index.self, from: $0) }
        let items = (index?.items ?? []).compactMap { $0.item(in: root) }.prefix(limit).map { $0 }
        discardDirectories(outside: items)
        return items
    }

    // MARK: - Deleting

    /// Everything under this root, index included. Used by the launch sweep and by turning
    /// history off — in the second case the user has just said "do not keep these", and
    /// leaving the bytes behind while hiding the list would be the wrong reading of that.
    func discardEverything() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Removes the directories backing these entries, best effort and silent: a file that
    /// outlives its entry is a privacy wart, not something the user can act on.
    ///
    /// The guard is the safety rail — an entry only ever names a directory *directly* under
    /// one of the two known roots, so a malformed URL deletes nothing.
    static func discard(_ items: [RecentItem]) {
        let roots = [session.root, history.root].map(\.standardizedFileURL.path)
        for item in items {
            let directory = item.fileURL.deletingLastPathComponent()
            guard roots.contains(directory.deletingLastPathComponent().standardizedFileURL.path) else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func contains(_ item: RecentItem) -> Bool {
        item.fileURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
            == root.standardizedFileURL.path
    }

    private func discardDirectories(outside items: [RecentItem]) {
        let live = Set(items.map { $0.fileURL.deletingLastPathComponent().lastPathComponent })
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in contents where url.hasDirectoryPath && !live.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - On-disk shape

    private struct Index: Codable {
        /// Bumped when the layout changes; a mismatch would be handled by ignoring the
        /// index, which is exactly what a decode failure already does.
        var version = 1
        var items: [Record]
    }

    private struct Record: Codable {
        var id: UUID
        var fingerprint: String
        var file: String
        var name: String
        var width: Int
        var height: Int
        var createdAt: Date

        init(_ item: RecentItem) {
            id = item.id
            fingerprint = item.fingerprint
            file = item.fileURL.lastPathComponent
            name = item.suggestedName
            width = item.pixelWidth
            height = item.pixelHeight
            createdAt = item.createdAt
        }

        func item(in root: URL) -> RecentItem? {
            let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
            let file = directory.appendingPathComponent(file)
            let thumbnail = directory.appendingPathComponent("thumbnail.png")
            guard FileManager.default.fileExists(atPath: file.path),
                  let thumbnailData = try? Data(contentsOf: thumbnail)
            else { return nil }
            return RecentItem(
                id: id,
                fingerprint: fingerprint,
                thumbnailPNG: thumbnailData,
                fileURL: file,
                originalURL: directory.appendingPathComponent("original.png"),
                suggestedName: name,
                pixelWidth: width,
                pixelHeight: height,
                createdAt: createdAt
            )
        }
    }
}
