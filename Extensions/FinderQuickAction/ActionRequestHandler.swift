import AppKit
import Foundation
import UniformTypeIdentifiers

/// The Finder Quick Action, and deliberately the thinnest possible one: it collects the
/// selected files and hands them to the main app, which runs them through the same
/// pipeline as a drop or a paste (`application(_:open:)`).
///
/// It does *not* matte anything itself, for a reason worth keeping written down: app
/// extensions must be sandboxed, and a sandboxed extension holding "user-selected
/// read-only" file access cannot write `photo.png` next to `photo.jpg` — the grant covers
/// the selected files, not their directory. Every silent-output design dies on that rock.
/// Bridging to the app costs one window appearing, and buys the full product: batch
/// placeholders, the comparison inspector, engine switching, honest failure sentences,
/// and exactly one implementation of the pipeline.
/// An `NSViewController`, not a bare request handler: `com.apple.ui-services` is the *UI*
/// action extension point — the only one Finder's Quick Actions menu accepts — and ShareKit
/// asserts on `viewController` at load time (crashed with "未能与帮助应用程序通信",
/// PluckQuickAction-2026-08-11-161430.ips). The view is empty and the request completes in
/// `viewDidLoad`, so nothing ever actually appears.
final class ActionViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let context = extensionContext else { return }
        forward(context)
    }

    private func forward(_ context: NSExtensionContext) {
        let providers = (context.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }

        guard !providers.isEmpty else {
            context.completeRequest(returningItems: nil)
            return
        }

        let group = DispatchGroup()
        // Collected with an index so the batch reaches the app in Finder's order, not in
        // whatever order the item providers happen to resolve.
        var slots = [URL?](repeating: nil, count: providers.count)
        let lock = NSLock()

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                let url: URL?
                switch item {
                case let value as URL: url = value
                case let value as Data: url = URL(dataRepresentation: value, relativeTo: nil)
                default: url = nil
                }
                if let url {
                    lock.lock()
                    slots[index] = url
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            let urls = slots.compactMap { $0 }
            guard !urls.isEmpty, let app = Self.mainAppURL() else {
                context.completeRequest(returningItems: nil)
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration) { _, _ in
                context.completeRequest(returningItems: nil)
            }
        }
    }

    /// The app this extension lives inside:
    /// `Pluck.app/Contents/PlugIns/PluckQuickAction.appex` → up three → `Pluck.app`.
    ///
    /// Resolved by position rather than by bundle-id lookup so a copy of Pluck in
    /// ~/Downloads launches *itself*, not whichever other copy LaunchServices likes today.
    static func mainAppURL() -> URL? {
        let app = Bundle.main.bundleURL
            .deletingLastPathComponent()   // PlugIns/
            .deletingLastPathComponent()   // Contents/
            .deletingLastPathComponent()   // Pluck.app
        return app.pathExtension == "app" ? app : nil
    }
}
