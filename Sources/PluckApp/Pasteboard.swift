import AppKit
import Foundation
import PluckKit
import UniformTypeIdentifiers

/// Narrow seam over `NSPasteboard` so the ⌥⌘B round trip can be tested headlessly.
protocol ImagePasteboard: Sendable {
    /// Raw encoded image bytes plus a name hint, or nil when the clipboard holds no image.
    func readImage() -> (data: Data, name: String)?
    func writePNG(_ data: Data)
}

/// Holds the pasteboard *name*, not the object: `NSPasteboard` is not `Sendable`, and the
/// clipboard round trip deliberately runs off the main actor.
struct SystemPasteboard: ImagePasteboard {
    let name: NSPasteboard.Name

    init(name: NSPasteboard.Name = .general) {
        self.name = name
    }

    private var pasteboard: NSPasteboard { NSPasteboard(name: name) }

    func readImage() -> (data: Data, name: String)? {
        let pasteboard = pasteboard
        // File URLs first: a copied Finder item carries the original encoding and
        // a real filename, both of which the flattened bitmap flavors throw away.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first(where: { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }),
           let data = try? Data(contentsOf: url) {
            return (data, url.deletingPathExtension().lastPathComponent)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return (data, L.s("Cutout"))
            }
        }
        return nil
    }

    func writePNG(_ data: Data) {
        let pasteboard = pasteboard
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }
}

enum ClipboardOutcome: Equatable, Sendable {
    case success
    case noImage
    case noSubject
    case failed
}

/// ⌘C → ⌥⌘B → ⌘V, with no dialogs on any path: failures are reported through the
/// status item, never a modal that steals focus from whatever the user was doing.
struct ClipboardPlucker: Sendable {
    let pasteboard: any ImagePasteboard
    let process: @Sendable (Data, String) async throws -> ProcessedImage

    init(
        pasteboard: any ImagePasteboard,
        process: @escaping @Sendable (Data, String) async throws -> ProcessedImage = PluckService.process(data:name:)
    ) {
        self.pasteboard = pasteboard
        self.process = process
    }

    func run() async -> (outcome: ClipboardOutcome, result: ProcessedImage?) {
        guard let input = pasteboard.readImage() else { return (.noImage, nil) }
        do {
            let processed = try await process(input.data, input.name)
            pasteboard.writePNG(processed.pngData)
            return (.success, processed)
        } catch PluckError.noSubjectDetected {
            return (.noSubject, nil)
        } catch let error as PluckError where error.kind == .imageLoadFailed {
            return (.noImage, nil)
        } catch {
            return (.failed, nil)
        }
    }
}
