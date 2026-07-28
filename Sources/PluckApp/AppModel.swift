import AppKit
import Foundation
import Observation
import PluckKit
import SwiftUI

/// Transient status-item feedback. v0.1 never interrupts with an alert: the icon is the
/// entire notification surface.
enum StatusFeedback: Equatable, Sendable {
    case idle
    case busy
    case success
    case failure
}

/// A job that has been accepted but has no result yet. It occupies a grid cell from the
/// instant the user drops or pastes, so the wait has a location on screen instead of being
/// a silent gap (decisions.md 2026-07-27).
struct PendingItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case running
        /// The reason travels with the cell so the grid and the status line cannot
        /// disagree about what went wrong.
        case failed(PluckFailure)
    }

    let id: UUID
    /// What the user called it. The grid never shows this — a 92pt tile has no room — but
    /// the batch list is a list of *files*, and a row that cannot say which one it is
    /// leaves the user counting positions to work out which of forty failed.
    let name: String
    /// The *input* thumbnail, filled in once the worker has decoded it — nil for the first
    /// few frames, and permanently nil if the bytes were not an image at all.
    var thumbnail: Data?
    var state: State = .running

    var failure: PluckFailure? {
        guard case .failed(let reason) = state else { return nil }
        return reason
    }
}

/// How far a multi-image drop has got. Counted in whole images because that is the only
/// unit anyone can measure: Vision reports no progress inside a single request, so a
/// per-image percentage would be an animation pretending to be information.
struct BatchProgress: Equatable, Sendable {
    var total: Int
    var done: Int

    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// A sentence for the status line, and whether it is bad news. Export writes here too, so
/// the line cannot assume everything it carries is a complaint.
struct StatusLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case info
        case warning
    }

    let kind: Kind
    let text: String
}

@MainActor
@Observable
final class AppModel {
    let recents = RecentStore()

    /// Rendered ahead of `recents.items`, so a new job appears where the result will land.
    private(set) var pendingItems: [PendingItem] = []

    /// The entry a duplicate pluck was folded into. Non-nil for ~900ms so the grid can
    /// flash its border — de-duplication has to be visible or it looks like a failure.
    private(set) var highlightedItemID: UUID?

    /// The shelf's status line, or nil for the standing drop hint. A failed cell can carry
    /// a red rim and nothing more; the reason needs a sentence, and the hint strip is the
    /// only place in v0.1 wide enough to hold one — it is also where the eye already is
    /// after a drop.
    private(set) var status: StatusLine?

    var statusMessage: String? { status?.text }

    /// Non-nil while a drop is being worked through. Only shown for more than one image:
    /// a single row's own spinner already says everything a "0 of 1 done" bar would.
    private(set) var batch: BatchProgress?

    /// What the main window's gallery has picked out. Owned here rather than in the view
    /// because two things outside it read the answer: the key monitor (⌘A, Esc — the window
    /// is AppKit's, and the shortcuts have to be caught before the responder chain turns them
    /// into text operations) and Export, whose file set *is* the selection.
    private(set) var selection = GallerySelection()

    /// A click on a card, with `extending` true when ⌘ was down.
    func select(_ item: RecentItem, extending: Bool = false) {
        selection.click(item.id, extending: extending)
    }

    func selectAll() {
        selection.selectAll(recents.items.map(\.id))
    }

    func clearSelection() {
        selection.clear()
    }

    /// The cutouts Export would write: the selection when there is one, otherwise the lot.
    /// The button says which of the two it is, so the two must be decided in one place.
    var exportTargets: [RecentItem] {
        selection.isEmpty ? recents.items : recents.items.selected(by: selection)
    }

    /// Called after anything removes entries from the grid.
    private func pruneSelection() {
        selection.prune(to: recents.items.map(\.id))
    }

    private(set) var feedback: StatusFeedback = .idle {
        didSet { onFeedbackChange?(feedback) }
    }

    /// The status item lives in AppKit; rather than mirror the state machine there,
    /// the delegate subscribes to the one owned here.
    var onFeedbackChange: (@MainActor (StatusFeedback) -> Void)?

    /// Same shape, same reason: the preview panel is an `NSPanel` owned by the delegate,
    /// so the grid asks for it rather than reaching into AppKit itself.
    var onPreviewRequest: (@MainActor (RecentItem) -> Void)?

    private let pasteboard: any ImagePasteboard
    /// The matting entry point for every path that starts from bytes. Injected for the
    /// same reason `ClipboardPlucker` takes one: the placeholder lifecycle is a state
    /// machine worth testing, and it should not need Vision to run. The file path keeps
    /// `PluckService.process(url:)` because the URL is also where the name comes from.
    private let process: @Sendable (Data, String, any MattingEngine) async throws -> ProcessedImage
    private let engines: EngineProvider
    private var inFlight = 0
    private var feedbackToken = 0
    private var highlightToken = 0
    private var statusToken = 0

    init(
        pasteboard: any ImagePasteboard = SystemPasteboard(),
        preferences: Preferences? = nil,
        engines: EngineProvider = .shared,
        process: @escaping @Sendable (Data, String, any MattingEngine) async throws -> ProcessedImage
            = PluckService.process(data:name:engine:)
    ) {
        self.pasteboard = pasteboard
        self.preferences = preferences
        self.engines = engines
        self.process = process
        guard let preferences else { return }
        // Order matters: restore first, then subscribe. Seeding through `onChange` would
        // have the store rewrite the index it was just read from.
        if preferences.keepsHistory {
            recents.restore(CutoutArchive.history.load(limit: RecentStore.defaultCapacity))
        }
        recents.onChange = { items in CutoutArchive.history.writeIndex(items) }
    }

    /// nil in tests, which have no business touching the real defaults or the real
    /// Application Support directory. A nil preference set means session behaviour:
    /// nothing is restored and nothing is persisted.
    private let preferences: Preferences?

    private var archive: CutoutArchive { preferences?.archive ?? .session }

    /// Switching the preference off forgets the list immediately, and the files go at the
    /// next launch (`AppDelegate` sweeps both roots when history is off).
    ///
    /// Not the other order. Entries already in the grid are backed by files under this
    /// root; deleting them now would leave the user looking at cells whose Copy, Save and
    /// drag-out have all quietly stopped working. What they asked for is not to be
    /// remembered next time, and that is what this does.
    func forgetStoredHistory() {
        CutoutArchive.history.writeIndex([])
    }

    // MARK: - Entry points

    func pluckClipboard() {
        let ticket = beginWork(name: L.s("Clipboard image"))
        let process = process
        // The weak capture is hoisted into its own `@Sendable` closure: a `[weak self]`
        // binding is implicitly mutable, and Swift 6 refuses to let a nested concurrent
        // closure (here, `run`'s `onInput`) capture it directly.
        let accept: @Sendable (Data) async -> Bool = { [weak self] data in
            // Both the decode and the hash happen out here. A SHA-256 of a 24-megapixel
            // PNG is tens of milliseconds, and the main actor is at this moment animating
            // the placeholder that was inserted for these very bytes.
            let thumbnail = await PluckService.inputThumbnail(data: data)
            let fingerprint = PluckService.fingerprint(data)
            return await self?.accept(fingerprint: fingerprint, thumbnail: thumbnail, ticket: ticket) ?? false
        }
        Task { [weak self] in
            guard let self else { return }
            let engine = await preparedEngine()
            let engineID = engine.id
            let plucker = ClipboardPlucker(pasteboard: pasteboard) { data, name in
                try await process(data, name, engine)
            }
            Task.detached(priority: .userInitiated) { [weak self] in
                let (outcome, processed) = await plucker.run { data in await accept(data) }
                await self?.deliver(
                    ticket: ticket,
                    outcome: outcome,
                    processed: processed,
                    engineID: engineID
                )
            }
        }
    }

    func handleDrop(_ payloads: [DroppedPayload]) {
        let process = process
        // Every placeholder goes in first, then the engine is resolved once for the whole
        // drop. Resolving per image would compile the same model ten times over, and
        // resolving before the placeholders would leave a ten-second gap in which the drop
        // appears to have been ignored.
        let tickets = payloads.map { beginWork(name: $0.displayName) }
        Task { [weak self] in
            guard let self else { return }
            let engine = await preparedEngine()
            let engineID = engine.id
            for (payload, ticket) in zip(payloads, tickets) {
                Task.detached(priority: .userInitiated) { [weak self] in
                    let thumbnail = await PluckService.inputThumbnail(of: payload)
                    let fingerprint = payload.bytes.map(PluckService.fingerprint)
                    let accepted = await self?.accept(fingerprint: fingerprint, thumbnail: thumbnail, ticket: ticket)
                    guard accepted == true else {
                        await self?.deliver(ticket: ticket, outcome: .superseded, processed: nil)
                        return
                    }
                    do {
                        let processed: ProcessedImage
                        switch payload {
                        case .file(let url):
                            processed = try await PluckService.process(url: url, engine: engine)
                        case .data(let data):
                            processed = try await process(data, L.s("Cutout"), engine)
                        }
                        await self?.deliver(
                            ticket: ticket,
                            outcome: .success,
                            processed: processed,
                            engineID: engineID
                        )
                    } catch {
                        await self?.deliver(ticket: ticket, outcome: .failure(PluckFailure(error)), processed: nil)
                    }
                }
            }
        }
    }

    /// The engine the user picked, loaded if it is not loaded yet.
    ///
    /// The first use of a downloaded model is a Core ML compile of a 94 MB package — 5–10
    /// seconds in which nothing else visibly happens (roadmap risk, decisions.md 2026-07-28).
    /// The placeholder cards are already on screen by then, so the wait has a location; this
    /// adds the sentence that says what the wait is *for*, through the same status line
    /// every other explanation goes through. No new UI, and nothing at all is said for
    /// Vision or for a model that is already in memory — the common case must stay silent.
    private func preparedEngine() async -> any MattingEngine {
        let id = preferences?.engineID ?? EngineCatalog.defaultEngineID
        var announced = false
        if await !engines.isReady(id) {
            report(.info, L.s("Getting the model ready — this takes a few seconds the first time."))
            announced = true
        }
        let resolved = await engines.resolve(id)
        if resolved.fellBackFrom != nil {
            report(.warning, L.s("That model couldn’t be loaded — using Apple Vision for now."))
        } else if announced {
            // The "getting ready" line has done its job; leaving it up would have it
            // outlive the wait it was explaining.
            clearStatus()
        }
        return resolved.engine
    }

    func preview(_ item: RecentItem) {
        onPreviewRequest?(item)
    }

    // MARK: - Re-plucking

    /// One engine, as the preview panel's switcher needs to say it.
    ///
    /// Every engine is always listed, including the one that made the cutout on screen: the
    /// menu is "which engine am I looking at this picture through", not a shrinking list of
    /// things left to try. A list that loses an entry each time it is used cannot be learned,
    /// and it hides the one fact the user is actually after — which engine this result is.
    struct EngineOption: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        /// What the click will cost in bytes, and nil once it costs nothing. An engine that
        /// is already on disk has nothing left to warn about — the parenthetical used to
        /// hold a duration ("~1–2 s") that was a guess about the user's machine, and a menu
        /// where every entry carries a parenthetical trains the eye to skip all of them,
        /// including the one that says 83 MB.
        let hint: String?
        let installed: Bool
        /// Whether this is the engine that made the cutout being shown — the tick in the menu,
        /// and the name on the button that opens it.
        let isCurrent: Bool

        /// How the switcher's menu says it.
        var menuTitle: String {
            guard let hint else { return label }
            return String(format: L.s("%1$@ (%2$@)"), label, hint)
        }
    }

    /// The entries currently being re-plucked, keyed by the cutout the request came from —
    /// so the panel showing it can say it is working, and so a second click on the same
    /// menu cannot queue the same job twice.
    private(set) var repluckingIDs: Set<UUID> = []

    func isRepluckRunning(_ item: RecentItem) -> Bool { repluckingIDs.contains(item.id) }

    /// Every engine this build knows about, with the one that made `item` ticked.
    func engineOptions(for item: RecentItem) async -> [EngineOption] {
        await engines.options.map { descriptor in
            EngineOption(
                id: descriptor.id,
                label: EngineLabels.name(descriptor.id, fallback: descriptor.model?.displayName),
                hint: descriptor.installed
                    ? nil
                    : EngineLabels.megabytes(descriptor.model?.bytes ?? 0),
                installed: descriptor.installed,
                isCurrent: descriptor.id == item.engineID
            )
        }
    }

    /// The cutout of this same picture that `engineID` has already produced, if the grid
    /// still holds one.
    ///
    /// "This picture" is the lineage, not the entry: re-plucking leaves two cutouts of one
    /// photo in the grid, and switching back and forth between them must not re-run anything.
    /// Static and pure because that is the whole rule, and the rule is what can be wrong.
    static func sibling(of item: RecentItem, engine engineID: String, in items: [RecentItem]) -> RecentItem? {
        items.first { $0.sourceID == item.sourceID && $0.engineID == engineID }
    }

    /// Points the preview at this picture as `engineID` sees it.
    ///
    /// A result that already exists is shown, not recomputed: the two cutouts of one photo
    /// are both on the shelf, and the user flipping between them to compare edges should
    /// cost nothing at all. Only a combination the grid has never held is work.
    func showEngine(_ engineID: String, for item: RecentItem) {
        guard engineID != item.engineID else { return }
        if let existing = Self.sibling(of: item, engine: engineID, in: recents.items) {
            preview(existing)
            return
        }
        repluck(item, with: engineID)
    }

    /// Runs this cutout's source picture through another engine, and files the result beside
    /// it instead of over it.
    ///
    /// Beside, because the two are not versions of one answer: lite's decided edge is the
    /// right cutout for a logo and the wrong one for a wine glass, and the user cannot know
    /// which they wanted until both are on screen. Overwriting would make the comparison
    /// cost a re-pluck of whatever was replaced.
    ///
    /// The input is the entry's stored `original.png`, which was downsampled to 1200px on
    /// the way in (`PluckService.previewMaxEdge`) — so a re-pluck of a 24-megapixel photo is
    /// a 1200px cutout. Keeping a full-resolution copy of every input against the chance of
    /// a second pass would multiply the archive's size for a feature most entries never use;
    /// the honest fix is re-dropping the file, which costs one drag.
    func repluck(_ item: RecentItem, with engineID: String) {
        guard !repluckingIDs.contains(item.id) else { return }
        repluckingIDs.insert(item.id)
        let ticket = beginWork(name: item.suggestedName)
        // The cutout's own thumbnail, so the placeholder cell shows the picture being worked
        // on from the first frame — unlike a drop, nothing here has to be decoded first.
        attach(thumbnail: item.thumbnailPNG, to: ticket)
        let process = process
        Task { [weak self] in
            guard let self else { return }
            defer { repluckingIDs.remove(item.id) }
            guard await install(engineID) else {
                finish(ticket: ticket, outcome: .failure(.modelUnavailable), item: nil)
                return
            }
            let resolved = await engines.resolve(engineID)
            // Falling back to Vision is right for a drop — the user wants their picture
            // plucked — and wrong here: they named an engine, and a Vision copy of a cutout
            // they already have is not a smaller version of that answer.
            guard resolved.fellBackFrom == nil else {
                finish(ticket: ticket, outcome: .failure(.modelUnavailable), item: nil)
                return
            }
            let engine = resolved.engine
            let name = item.suggestedName
            let sourceID = item.sourceID
            await Task.detached(priority: .userInitiated) { [weak self] in
                guard let data = item.originalPNG() else {
                    await self?.deliver(ticket: ticket, outcome: .failure(.fileGone), processed: nil)
                    return
                }
                do {
                    let processed = try await process(data, name, engine)
                    await self?.deliver(
                        ticket: ticket,
                        outcome: .success,
                        processed: processed,
                        engineID: engine.id,
                        sourceID: sourceID,
                        previews: true
                    )
                } catch {
                    await self?.deliver(
                        ticket: ticket,
                        outcome: .failure(PluckFailure(error)),
                        processed: nil
                    )
                }
            }.value
        }
    }

    /// True once the model is on disk. Says so on the status line while it is not, because
    /// 83 MB is long enough that a spinner alone reads as a hang.
    private func install(_ id: String) async -> Bool {
        guard await !engines.isInstalled(id) else { return true }
        report(.info, String(format: L.s("Downloading %@…"), EngineLabels.name(id)))
        do {
            try await engines.install(id)
            clearStatus()
            return true
        } catch {
            // The reason reaches the user through the failed placeholder's own sentence,
            // which `finish` puts on the same line this one is sitting on.
            return false
        }
    }

    func copy(_ item: RecentItem) {
        Task { [weak self] in
            guard let self else { return }
            // The bytes live on disk now, so this can fail — a file deleted underneath us,
            // or a write that failed when the entry was made. Silently copying nothing
            // would be the worst of the three possible outcomes.
            guard let data = await Self.bytes(of: item) else { return reportMissingFile() }
            pasteboard.writePNG(data)
            flash(.success)
        }
    }

    func save(_ item: RecentItem) {
        Task { [weak self] in
            guard let self else { return }
            guard let data = await Self.bytes(of: item) else { return reportMissingFile() }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = item.suggestedName + ".png"
            panel.allowedContentTypes = [.png]
            panel.title = L.s("Save cutout")
            NSApp.activate()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            // Same confirmation Copy gives. The panel closing means "the dialog is done",
            // not "the bytes are on disk", and those are not the same event.
            flash(await Self.write(data, to: url) ? .success : .failure)
        }
    }

    /// Reading a cutout back is `Data(contentsOf:)` on a file that is routinely megabytes,
    /// and both callers are buttons in a panel that is still animating. `nonisolated async`
    /// is the whole mechanism: it puts the read on the cooperative pool, and the caller's
    /// `Task` is already on the main actor for the part that has to be.
    private nonisolated static func bytes(of item: RecentItem) async -> Data? { item.pngData() }

    private nonisolated static func write(_ data: Data, to url: URL) async -> Bool {
        (try? data.write(to: url, options: .atomic)) != nil
    }

    private func reportMissingFile() {
        report(.warning, PluckFailure.fileGone.message)
        flash(.failure)
    }

    /// Writes what the export button is offering — the selection, or the whole grid — into
    /// one directory.
    ///
    /// A directory picker rather than a silent write to the remembered folder: twenty files
    /// appearing somewhere the user has to remember choosing, months ago, is not a
    /// convenience. Remembering the folder makes the picker open where it opened last,
    /// which is the part that was actually tedious.
    func exportTargeted() {
        export(exportTargets)
    }

    private func export(_ items: [RecentItem]) {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = L.s("Export cutouts")
        panel.message = L.s("Choose a folder for the cutouts")
        panel.prompt = L.s("Export")
        if let remembered = preferences?.exportDirectory {
            panel.directoryURL = remembered
        }
        NSApp.activate()
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        preferences?.exportDirectory = directory
        // Oldest first, so that when two cutouts want the same filename the numbering runs
        // in the order the images were plucked rather than backwards.
        let ordered = items.reversed().map { $0 }
        Task.detached(priority: .userInitiated) { [weak self] in
            let written = Self.write(ordered, into: directory)
            await self?.reportExport(written: written, of: ordered.count)
        }
    }

    private func reportExport(written: Int, of total: Int) {
        if written == total {
            report(.info, String(format: L.s("Exported %d cutouts."), written))
            flash(.success)
        } else {
            report(.warning, String(format: L.s("Exported %1$d of %2$d — the rest could not be written."), written, total))
            flash(.failure)
        }
    }

    /// Returns how many landed. Nonisolated because twenty PNGs is enough writing to be
    /// felt on the main actor, and the panel has already closed by the time it starts.
    private nonisolated static func write(_ items: [RecentItem], into directory: URL) -> Int {
        items.reduce(into: 0) { written, item in
            guard let data = item.pngData() else { return }
            let url = availableURL(in: directory, name: item.suggestedName)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            written += 1
        }
    }

    /// Never overwrites. Two plucks of two different `IMG_0042.jpg`s from two folders is
    /// the ordinary case, not the exotic one, and silently keeping only the second would
    /// destroy work the user cannot get back.
    nonisolated static func availableURL(in directory: URL, name: String) -> URL {
        func candidate(_ suffix: String) -> URL {
            directory.appendingPathComponent(name + suffix).appendingPathExtension("png")
        }
        let first = candidate("")
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        for n in 2...999 where !FileManager.default.fileExists(atPath: candidate(" \(n)").path) {
            return candidate(" \(n)")
        }
        return candidate(" \(UUID().uuidString)")
    }

    /// No confirmation sheet: Clear is one press and the grid is not a library. The files
    /// go with the entries — they are cutouts of the user's photos, and keeping them after
    /// an explicit "clear" would quietly contradict the privacy claim.
    func clearRecents() {
        highlightedItemID = nil
        let cleared = withAnimation(.easeInOut(duration: 0.2)) { recents.clear() }
        pruneSelection()
        discard(cleared)
    }

    /// One entry, on the user's say-so. Same contract as Clear at a smaller scale: the row
    /// goes and its files go with it, without a confirmation sheet — the grid is a shelf of
    /// results that can be plucked again, not a library.
    func discard(_ item: RecentItem) {
        if highlightedItemID == item.id { highlightedItemID = nil }
        let removed = withAnimation(.easeInOut(duration: 0.2)) { recents.remove(item.id) }
        pruneSelection()
        discard([removed].compactMap { $0 })
    }

    private func discard(_ items: [RecentItem]) {
        guard !items.isEmpty else { return }
        Task.detached(priority: .utility) { CutoutArchive.discard(items) }
    }

    // MARK: - Bookkeeping

    /// Returns the ticket that ties a placeholder cell to the worker that will replace it.
    private func beginWork(name: String) -> UUID {
        // A batch is "everything queued while something was still queued". Dropping ten
        // files calls this ten times in one turn of the run loop, so the first call starts
        // the count and the other nine join it; a drop that arrives after the list has
        // drained starts a fresh one rather than resuming a finished total.
        //
        // "Still queued" means *running*, not "present": a failed placeholder lingers for
        // 2.2 seconds with its red rim (see `fail`), and a drop that arrives in that window
        // used to be counted onto the batch it had nothing to do with — one image reported
        // as "5 of 6".
        if !pendingItems.contains(where: { $0.state == .running }) {
            batch = BatchProgress(total: 0, done: 0)
        }
        batch?.total += 1
        inFlight += 1
        feedback = .busy
        // A new attempt supersedes the last complaint. Leaving it up would let a stale
        // "no subject found" sit over a drop that is going perfectly well.
        clearStatus()
        let pending = PendingItem(id: UUID(), name: name)
        withAnimation(.easeOut(duration: 0.18)) {
            pendingItems.insert(pending, at: 0)
        }
        return pending.id
    }

    /// Shows the input on the placeholder, and answers whether the job is worth running.
    ///
    /// False means these exact bytes are already a cutout in the grid. That is not a corner
    /// case: every clipboard pluck writes its result back to the clipboard, so a second ⌘V
    /// hands the output straight back in — and plucking a cutout is *not* idempotent (each
    /// pass shaves the alpha edge again, so the bytes differ every time). Left to run, it
    /// fills the grid with near-copies, each one slightly worse than the last, and leaves the
    /// worst of them on the clipboard. Dragging a saved cutout back in is the same fingerprint
    /// by the same route.
    ///
    /// Takes the hash rather than the bytes: computing it is a full pass over the input, and
    /// every caller is already off the main actor when it has them.
    private func accept(fingerprint: String?, thumbnail: Data?, ticket: UUID) -> Bool {
        attach(thumbnail: thumbnail, to: ticket)
        guard let fingerprint, let existing = recents.promote(fingerprint: fingerprint) else { return true }
        highlight(existing)
        return false
    }

    private func attach(thumbnail: Data?, to ticket: UUID) {
        guard let thumbnail, let index = pendingItems.firstIndex(where: { $0.id == ticket }) else { return }
        pendingItems[index].thumbnail = thumbnail
    }

    /// The tail of every job, and deliberately `nonisolated`: storing a cutout is three
    /// atomic writes plus a SHA-256 over the full-size PNG, which on the main actor is a
    /// visible freeze *per image* — a hundred-file drop was a hundred stutters. Only the
    /// finished entry crosses back.
    ///
    /// A write that fails is still a job that failed. The file *is* the entry (see
    /// `CutoutArchive`), so there is no in-memory copy to fall back on, and a cell whose
    /// Copy, Save, preview and drag all do nothing is worse than an honest error.
    private nonisolated func deliver(
        ticket: UUID,
        outcome: PluckOutcome,
        processed: ProcessedImage?,
        engineID: String = EngineCatalog.defaultEngineID,
        sourceID: UUID? = nil,
        previews: Bool = false
    ) async {
        guard case .success = outcome, let processed else {
            await finish(ticket: ticket, outcome: outcome, item: nil)
            return
        }
        // Read per cutout rather than captured when the drop arrived, so flipping the
        // history preference takes effect on the next file rather than the next launch.
        let archive = await self.archive
        guard let item = try? archive.store(processed, id: ticket, engineID: engineID, sourceID: sourceID) else {
            await finish(ticket: ticket, outcome: .failure(.notWritten), item: nil)
            return
        }
        await finish(ticket: ticket, outcome: .success, item: item, previews: previews)
    }

    private func finish(ticket: UUID, outcome: PluckOutcome, item: RecentItem?, previews: Bool = false) {
        inFlight = max(0, inFlight - 1)
        // Every exit from here is one image resolved, including the ones that failed and
        // the ones that turned out to be duplicates. A bar that only counted successes
        // would stall short of full on a batch with one bad file in it and never explain why.
        batch?.done += 1
        // Nothing was produced and nothing went wrong: the entry this job would have
        // duplicated is already flashing its border, which is the whole answer.
        if case .superseded = outcome {
            withAnimation(.easeInOut(duration: 0.25)) { pendingItems.removeAll { $0.id == ticket } }
            flash(.success)
            return
        }
        // A `.success` with no entry is a bug, not a user-facing state; treat it as the
        // generic failure rather than silently dropping the placeholder on the floor.
        // `deliver` has already turned a failed write into `.failure(.notWritten)`.
        guard case .success = outcome, let item else {
            fail(ticket, reason: outcome.failureReason ?? .unknown)
            flash(.failure)
            return
        }
        // The result inherits the ticket's identity rather than minting a new one — the
        // archive is handed the ticket as the entry id for exactly that reason. The grid
        // renders placeholders and results in one list keyed by this id, so carrying it
        // across is what makes completion a content change on the cell the user is already
        // watching instead of a removal plus an unrelated insertion.
        //
        // Both mutations inside one animation so the placeholder and the result cross-fade
        // in the same grid slot instead of the row jumping.
        let result = withAnimation(.easeInOut(duration: 0.25)) { () -> InsertResult in
            pendingItems.removeAll { $0.id == ticket }
            return recents.insert(item)
        }
        // A promotion keeps the entry that is already in the grid, which leaves the files
        // just written with nothing pointing at them — and Clear only knows about the ones
        // the store holds. Eviction is the same story from the other end of the list.
        if let existing = result.promoted {
            highlight(existing)
            discard([item])
        }
        discard(result.evicted)
        // The oldest entries fall off the end of a fixed-capacity list, and one of them may
        // well have been selected while the user was dropping the batch that pushed it off.
        if !result.evicted.isEmpty { pruneSelection() }
        flash(.success)
        // A re-pluck was asked for from the panel that is still showing the old cutout, so
        // the panel is where the answer belongs. Only on a genuine insert: a promotion means
        // the grid already held these exact bytes, and the cell it flashes is the answer.
        if previews, result.promoted == nil { preview(item) }
    }

    /// A failed job keeps its cell for a beat with a red rim and puts its reason in the
    /// status line. The cell vanishing instantly would be indistinguishable from the drop
    /// never having registered; the rim alone would be indistinguishable from any other
    /// failure.
    private func fail(_ ticket: UUID, reason: PluckFailure) {
        report(.warning, reason.message)
        guard let index = pendingItems.firstIndex(where: { $0.id == ticket }) else { return }
        pendingItems[index].state = .failed(reason)
        Task { @MainActor in
            // Longer than the old 1.2s: the cell and the sentence explaining it should be
            // on screen together long enough to be connected.
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                self.pendingItems.removeAll { $0.id == ticket }
            }
        }
    }

    /// Shown until superseded or until it has had time to be read. Not sticky: an error
    /// that outlives the situation that produced it is worse than none, because the user
    /// starts distrusting the line it sits in.
    private func report(_ kind: StatusLine.Kind, _ message: String) {
        statusToken += 1
        let token = statusToken
        withAnimation(.easeOut(duration: 0.18)) { status = StatusLine(kind: kind, text: message) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard token == self.statusToken else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.status = nil }
        }
    }

    private func clearStatus() {
        statusToken += 1
        guard status != nil else { return }
        withAnimation(.easeOut(duration: 0.18)) { status = nil }
    }

    private func highlight(_ id: UUID) {
        highlightedItemID = id
        highlightToken += 1
        let token = highlightToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard token == self.highlightToken else { return }
            self.highlightedItemID = nil
        }
    }

    private func flash(_ state: StatusFeedback) {
        feedback = state
        feedbackToken += 1
        let token = feedbackToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard token == self.feedbackToken else { return }
            self.feedback = self.inFlight > 0 ? .busy : .idle
        }
    }
}
