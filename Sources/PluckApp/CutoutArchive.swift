import Foundation
import PluckKit

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
/// How much disk a directory tree is really using.
///
/// Allocated size rather than logical size: what a user is deciding about when they read
/// "412 MB" beside a Clear button is how much space they get back, and on APFS a 900-byte
/// file still costs a block. Missing directories are zero rather than an error — an archive
/// that has never been written to costs nothing, which is the correct answer and not a
/// failure to compute one.
enum DirectorySize {
    static func bytes(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walk = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: nil
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walk {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

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
    func store(
        _ processed: ProcessedImage,
        id: UUID,
        engineID: String = EngineCatalog.defaultEngineID,
        sourceID: UUID? = nil
    ) throws -> RecentItem {
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
            pixelHeight: processed.height,
            engineID: engineID,
            sourceID: sourceID
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
        // Sweep orphans only on the word of an index that actually decoded. A missing or
        // corrupt index used to read as "everything here is an orphan" — one bad byte in
        // one JSON file and every cutout on disk was silently deleted at launch. Losing
        // the sweep for one session is nothing; losing the archive is everything.
        if index != nil {
            discardDirectories(outside: items)
        }
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
            let isHistory = directory.deletingLastPathComponent().standardizedFileURL.path
                == history.root.standardizedFileURL.path
            // History goes to the Trash, not into the void: Clear and Delete run without a
            // confirmation sheet, so the safety net has to live after the click instead of
            // in front of it. Session entries are temp files and can simply go.
            if isHistory {
                do {
                    try FileManager.default.trashItem(at: directory, resultingItemURL: nil)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                }
            } else {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    // MARK: - Measuring

    /// What this archive is costing the user, in bytes on disk.
    ///
    /// Walked, not tracked. A running total would be one more thing that has to be right
    /// across every path that writes, promotes, evicts, trashes or sweeps an entry — and the
    /// first time it drifted, the number in Settings would be a confident lie about disk
    /// usage in an app whose whole pitch is that it is honest about where the bytes are.
    /// Walking a few hundred files takes milliseconds and is always the truth.
    ///
    /// Callers run it off the main actor: `CutoutArchive` is a `Sendable` value and this
    /// function touches nothing else.
    func totalBytes() -> Int64 { DirectorySize.bytes(of: root) }

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

    /// One line of the index.
    ///
    /// New fields are decoded with `decodeIfPresent` and a default, and that is a rule rather
    /// than a convenience: the index written by the previous version is the user's history,
    /// and a synthesized `init(from:)` would throw on the first missing key — which `load`
    /// turns into "no index", which is an archive that silently empties itself on the launch
    /// after an update. `version` cannot save it either; bumping it means the same thing.
    /// A field that cannot state what its absence means does not belong in here.
    private struct Record: Codable {
        var id: UUID
        var fingerprint: String
        var file: String
        var name: String
        var width: Int
        var height: Int
        var createdAt: Date
        /// Absent in indexes written before engines could be chosen per cutout — everything
        /// Pluck had made until then came out of Vision, so that is what their absence says.
        var engineID: String
        /// Absent for the same reason, and an entry with no recorded lineage is a lineage of
        /// one: nothing else on disk claims to be a re-pluck of it.
        var sourceID: UUID

        init(_ item: RecentItem) {
            id = item.id
            fingerprint = item.fingerprint
            file = item.fileURL.lastPathComponent
            name = item.suggestedName
            width = item.pixelWidth
            height = item.pixelHeight
            createdAt = item.createdAt
            engineID = item.engineID
            sourceID = item.sourceID
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            fingerprint = try container.decode(String.self, forKey: .fingerprint)
            file = try container.decode(String.self, forKey: .file)
            name = try container.decode(String.self, forKey: .name)
            width = try container.decode(Int.self, forKey: .width)
            height = try container.decode(Int.self, forKey: .height)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            engineID = try container.decodeIfPresent(String.self, forKey: .engineID)
                ?? EngineCatalog.defaultEngineID
            sourceID = try container.decodeIfPresent(UUID.self, forKey: .sourceID) ?? id
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
                createdAt: createdAt,
                engineID: engineID,
                sourceID: sourceID
            )
        }
    }
}
