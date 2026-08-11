import AppKit
import Foundation
import PluckKit
import UniformTypeIdentifiers

/// What a ⌘V actually found. Three answers, because the clipboard has three shapes worth
/// distinguishing: copied files (a batch, with real filenames), a bare bitmap (a
/// screenshot, a browser image), and nothing usable at all.
enum ClipboardContent: Equatable, Sendable {
    case files([URL])
    case bitmap(data: Data, name: String)
    case none
}

/// Narrow seam over `NSPasteboard` so the clipboard round trip can be tested headlessly.
protocol ImagePasteboard: Sendable {
    func read() -> ClipboardContent
    func writePNG(_ data: Data)
}

/// Holds the pasteboard *name*, not the object — and hops to the main thread for every
/// call. `NSPasteboard` is not merely non-`Sendable`: its *methods* are not thread-safe.
/// `readObjectsForClasses` updates an internal type cache, and running that on a detached
/// task while the main thread also touches the pasteboard (a ⌘C an instant before the ⌘V)
/// corrupts the malloc heap — a real crash, `Pluck-2026-08-11-103001.ips`, aborting in
/// `___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED` under
/// `-[NSPasteboard _updateTypeCacheIfNeeded]`. The matting stays off the main actor; the
/// two pasteboard round trips are microseconds and belong to the thread AppKit owns.
struct SystemPasteboard: ImagePasteboard {
    let name: NSPasteboard.Name

    init(name: NSPasteboard.Name = .general) {
        self.name = name
    }

    /// Runs `body` on the main thread, wherever the caller happens to be. `sync` from a
    /// background task cannot deadlock here: nothing on the main thread ever blocks
    /// waiting for the detached pluck that calls this.
    private func onMain<T: Sendable>(_ body: @Sendable @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { body() }
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { body() } }
    }

    func read() -> ClipboardContent {
        onMain { readOnMain() }
    }

    @MainActor
    private func readOnMain() -> ClipboardContent {
        let pasteboard = NSPasteboard(name: name)
        // File URLs first: copied Finder items carry the original encodings and real
        // filenames, both of which the flattened bitmap flavors throw away. *All* of them —
        // a ⌘C over five photos is a batch, and taking the first was silently dropping four.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            let images = urls.filter {
                UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
            }
            // Files that are not images are the answer "no", not a reason to fall through:
            // Finder parks an *icon bitmap* beside the file URLs, and the fallback below
            // would happily matte a 512px generic-document icon.
            return images.isEmpty ? .none : .files(images)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                // What the row and the exported file will be called. "Cutout" named every
                // pasted image after what Pluck was about to do to it, which in a list of
                // twenty is twenty rows called the same thing; where it came from is the
                // only fact about it anyone has.
                return .bitmap(data: data, name: L.s("Clipboard"))
            }
        }
        return .none
    }

    func writePNG(_ data: Data) {
        onMain {
            let pasteboard = NSPasteboard(name: name)
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        }
    }
}

/// ⌘C → ⌘V in the popover → ⌘V wherever you were going: the cutout is written straight
/// back to the clipboard, so nothing touches disk. No dialogs on any path — failures are
/// reported through the status item and the shelf's status line, never a modal that steals
/// focus.
struct ClipboardPlucker: Sendable {
    let pasteboard: any ImagePasteboard
    let process: @Sendable (Data, String) async throws -> ProcessedImage

    init(
        pasteboard: any ImagePasteboard,
        process: @escaping @Sendable (Data, String) async throws -> ProcessedImage
            = { data, name in try await PluckService.process(data: data, name: name) }
    ) {
        self.pasteboard = pasteboard
        self.process = process
    }

    /// `onInput` fires with the raw clipboard bytes before matting starts, so the caller can
    /// put a placeholder on screen that shows *which* picture is being worked on — and can
    /// refuse the job by returning false. Refusing has to be possible *here*, before the
    /// engine runs: this type writes its result back to the clipboard, so a job that turns
    /// out to be redundant has already overwritten the user's clipboard by the time anyone
    /// downstream could throw the result away.
    func run(onInput: @Sendable (Data) async -> Bool = { _ in true }) async -> (outcome: PluckOutcome, result: ProcessedImage?) {
        // Bitmaps only: copied *files* take the drop pipeline (`AppModel.pluckClipboard`
        // routes them before this type is involved), because a file batch wants filenames
        // and placelholder-per-file, and writing one cutout back over a five-file clipboard
        // would answer a question nobody asked.
        guard case .bitmap(let data, let name) = pasteboard.read() else { return (.failure(.noInput), nil) }
        guard await onInput(data) else { return (.superseded, nil) }
        do {
            let processed = try await process(data, name)
            pasteboard.writePNG(processed.pngData)
            return (.success, processed)
        } catch {
            return (.failure(PluckFailure(error)), nil)
        }
    }
}
