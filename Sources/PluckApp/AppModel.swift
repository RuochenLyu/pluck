import AppKit
import Foundation
import Observation
import PluckKit

/// Transient status-item feedback. v0.1 never interrupts with an alert: the icon is the
/// entire notification surface.
enum StatusFeedback: Equatable, Sendable {
    case idle
    case busy
    case success
    case failure
}

@MainActor
@Observable
final class AppModel {
    let recents = RecentStore()
    private(set) var feedback: StatusFeedback = .idle {
        didSet { onFeedbackChange?(feedback) }
    }

    /// The status item lives in AppKit; rather than mirror the state machine there,
    /// the delegate subscribes to the one owned here.
    var onFeedbackChange: (@MainActor (StatusFeedback) -> Void)?

    private let pasteboard: any ImagePasteboard
    private var inFlight = 0
    private var feedbackToken = 0

    init(pasteboard: any ImagePasteboard = SystemPasteboard()) {
        self.pasteboard = pasteboard
    }

    // MARK: - Entry points

    func pluckClipboard() {
        beginWork()
        let plucker = ClipboardPlucker(pasteboard: pasteboard)
        Task.detached(priority: .userInitiated) { [weak self] in
            let (outcome, processed) = await plucker.run()
            await self?.finish(outcome: outcome, processed: processed)
        }
    }

    func handleDrop(_ payloads: [DroppedPayload]) {
        for payload in payloads {
            beginWork()
            Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let processed: ProcessedImage
                    switch payload {
                    case .file(let url):
                        processed = try await PluckService.process(url: url)
                    case .data(let data):
                        processed = try await PluckService.process(data: data, name: L.s("Cutout"))
                    }
                    await self?.finish(outcome: .success, processed: processed)
                } catch PluckError.noSubjectDetected {
                    await self?.finish(outcome: .noSubject, processed: nil)
                } catch {
                    await self?.finish(outcome: .failed, processed: nil)
                }
            }
        }
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
        } catch {
            flash(.failure)
        }
    }

    // MARK: - Bookkeeping

    private func beginWork() {
        inFlight += 1
        feedback = .busy
    }

    private func finish(outcome: ClipboardOutcome, processed: ProcessedImage?) {
        inFlight = max(0, inFlight - 1)
        if let processed {
            let id = UUID()
            let url = (try? PluckService.writeTemporaryFile(processed, id: id))
                ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(id).png")
            recents.insert(
                RecentItem(
                    id: id,
                    fingerprint: PluckService.fingerprint(processed.pngData),
                    pngData: processed.pngData,
                    thumbnailPNG: processed.thumbnailPNG,
                    fileURL: url,
                    suggestedName: processed.suggestedName
                )
            )
        }
        flash(outcome == .success ? .success : .failure)
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
