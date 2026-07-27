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
    /// The *input* thumbnail, filled in once the worker has decoded it — nil for the first
    /// few frames, and permanently nil if the bytes were not an image at all.
    var thumbnail: Data?
    var state: State = .running

    var failure: PluckFailure? {
        guard case .failed(let reason) = state else { return nil }
        return reason
    }
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
    private(set) var statusMessage: String?

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
    private let process: @Sendable (Data, String) async throws -> ProcessedImage
    private var inFlight = 0
    private var feedbackToken = 0
    private var highlightToken = 0
    private var statusToken = 0

    init(
        pasteboard: any ImagePasteboard = SystemPasteboard(),
        process: @escaping @Sendable (Data, String) async throws -> ProcessedImage = PluckService.process(data:name:)
    ) {
        self.pasteboard = pasteboard
        self.process = process
    }

    // MARK: - Entry points

    func pluckClipboard() {
        let ticket = beginWork()
        let plucker = ClipboardPlucker(pasteboard: pasteboard, process: process)
        // The weak capture is hoisted into its own `@Sendable` closure: a `[weak self]`
        // binding is implicitly mutable, and Swift 6 refuses to let a nested concurrent
        // closure (here, `run`'s `onInput`) capture it directly.
        let accept: @Sendable (Data) async -> Bool = { [weak self] data in
            let thumbnail = PluckService.inputThumbnail(data: data)
            return await self?.accept(input: data, thumbnail: thumbnail, ticket: ticket) ?? false
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let (outcome, processed) = await plucker.run { data in await accept(data) }
            await self?.finish(ticket: ticket, outcome: outcome, processed: processed)
        }
    }

    func handleDrop(_ payloads: [DroppedPayload]) {
        let process = process
        for payload in payloads {
            let ticket = beginWork()
            Task.detached(priority: .userInitiated) { [weak self] in
                let thumbnail = PluckService.inputThumbnail(of: payload)
                let accepted = await self?.accept(input: payload.bytes, thumbnail: thumbnail, ticket: ticket)
                guard accepted == true else {
                    await self?.finish(ticket: ticket, outcome: .superseded, processed: nil)
                    return
                }
                do {
                    let processed: ProcessedImage
                    switch payload {
                    case .file(let url):
                        processed = try await PluckService.process(url: url)
                    case .data(let data):
                        processed = try await process(data, L.s("Cutout"))
                    }
                    await self?.finish(ticket: ticket, outcome: .success, processed: processed)
                } catch {
                    await self?.finish(ticket: ticket, outcome: .failure(PluckFailure(error)), processed: nil)
                }
            }
        }
    }

    func preview(_ item: RecentItem) {
        onPreviewRequest?(item)
    }

    func copy(_ item: RecentItem) {
        pasteboard.writePNG(item.pngData)
        flash(.success)
    }

    func save(_ item: RecentItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedName + ".png"
        panel.allowedContentTypes = [.png]
        panel.title = L.s("Save cutout")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try item.pngData.write(to: url, options: .atomic)
            // Same confirmation Copy gives. The panel closing means "the dialog is done", not
            // "the bytes are on disk", and those are not the same event.
            flash(.success)
        } catch {
            flash(.failure)
        }
    }

    /// No confirmation sheet: the grid is session scratch, not a library. The temp copies
    /// go with it — they are the user's photos, and leaving them in `/tmp` after an
    /// explicit "clear" would quietly contradict the privacy claim.
    func clearRecents() {
        highlightedItemID = nil
        let urls = withAnimation(.easeInOut(duration: 0.2)) { recents.clear() }
        discardTemporaryFiles(at: urls)
    }

    private func discardTemporaryFile(at url: URL) {
        discardTemporaryFiles(at: [url])
    }

    /// Best effort and silent: a temp file that outlives its entry is a privacy wart, not
    /// an error the user can act on. The guard is the safety rail — only ever remove
    /// directories this app minted, `<tmp>/Pluck/<uuid>/`.
    private func discardTemporaryFiles(at urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                let directory = url.deletingLastPathComponent()
                guard directory.deletingLastPathComponent().lastPathComponent == "Pluck" else { continue }
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    // MARK: - Bookkeeping

    /// Returns the ticket that ties a placeholder cell to the worker that will replace it.
    private func beginWork() -> UUID {
        inFlight += 1
        feedback = .busy
        // A new attempt supersedes the last complaint. Leaving it up would let a stale
        // "no subject found" sit over a drop that is going perfectly well.
        clearStatus()
        let pending = PendingItem(id: UUID())
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
    private func accept(input: Data?, thumbnail: Data?, ticket: UUID) -> Bool {
        attach(thumbnail: thumbnail, to: ticket)
        guard let input,
              let existing = recents.promote(fingerprint: PluckService.fingerprint(input))
        else { return true }
        highlight(existing)
        return false
    }

    private func attach(thumbnail: Data?, to ticket: UUID) {
        guard let thumbnail, let index = pendingItems.firstIndex(where: { $0.id == ticket }) else { return }
        pendingItems[index].thumbnail = thumbnail
    }

    private func finish(ticket: UUID, outcome: PluckOutcome, processed: ProcessedImage?) {
        inFlight = max(0, inFlight - 1)
        // Nothing was produced and nothing went wrong: the entry this job would have
        // duplicated is already flashing its border, which is the whole answer.
        if case .superseded = outcome {
            withAnimation(.easeInOut(duration: 0.25)) { pendingItems.removeAll { $0.id == ticket } }
            flash(.success)
            return
        }
        // A `.success` with no image is a bug, not a user-facing state; treat it as the
        // generic failure rather than silently dropping the placeholder on the floor.
        guard case .success = outcome, let processed else {
            fail(ticket, reason: outcome.failureReason ?? .unknown)
            flash(.failure)
            return
        }
        // The result inherits the ticket's identity rather than minting a new one. The grid
        // renders placeholders and results in one list keyed by this id, so carrying it
        // across is what makes completion a content change on the cell the user is already
        // watching instead of a removal plus an unrelated insertion.
        let id = ticket
        // If the temp copy could not be written, this URL names a file that does not exist —
        // deliberately. `NSItemProvider(contentsOf:)` returns nil for it, so the drag simply
        // does nothing, while Copy, Save and the preview all keep working off `pngData`.
        // Losing one of four ways out beats losing the result.
        let url = (try? PluckService.writeTemporaryFile(processed, id: id))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(id).png")
        let item = RecentItem(
            id: id,
            fingerprint: PluckService.fingerprint(processed.pngData),
            pngData: processed.pngData,
            thumbnailPNG: processed.thumbnailPNG,
            originalPNG: processed.originalPNG,
            fileURL: url,
            suggestedName: processed.suggestedName,
            pixelWidth: processed.width,
            pixelHeight: processed.height
        )
        // Both mutations inside one animation so the placeholder and the result cross-fade
        // in the same grid slot instead of the row jumping.
        let result = withAnimation(.easeInOut(duration: 0.25)) { () -> InsertResult in
            pendingItems.removeAll { $0.id == ticket }
            return recents.insert(item)
        }
        // A promotion keeps the entry that is already in the grid, which leaves the copy
        // just written to /tmp with nothing pointing at it — and `clearRecents` only knows
        // about files the store holds. Re-plucking the same picture must not quietly grow
        // a pile of orphans.
        if case .promoted(let existing) = result {
            highlight(existing)
            discardTemporaryFile(at: url)
        }
        flash(.success)
    }

    /// A failed job keeps its cell for a beat with a red rim and puts its reason in the
    /// status line. The cell vanishing instantly would be indistinguishable from the drop
    /// never having registered; the rim alone would be indistinguishable from any other
    /// failure.
    private func fail(_ ticket: UUID, reason: PluckFailure) {
        report(reason.message)
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
    private func report(_ message: String) {
        statusToken += 1
        let token = statusToken
        withAnimation(.easeOut(duration: 0.18)) { statusMessage = message }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard token == self.statusToken else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.statusMessage = nil }
        }
    }

    private func clearStatus() {
        statusToken += 1
        guard statusMessage != nil else { return }
        withAnimation(.easeOut(duration: 0.18)) { statusMessage = nil }
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
