import AppKit
import SwiftUI

/// Pluck's own About panel, in place of `orderFrontStandardAboutPanel`.
///
/// The standard panel takes a credits blob and nothing else. What this app has to say in
/// About is where the source is and what licence it and its model are under — that is the
/// product, for something free and open source — and those are links, which a credits
/// string cannot be without smuggling a URL past the user as underlined text.
@MainActor
final class AboutWindowController {
    static let repository = URL(string: "https://github.com/RuochenLyu/pluck")!
    static let licence = URL(string: "https://github.com/RuochenLyu/pluck/blob/main/LICENSE")!

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = make()
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// `AboutView` retranslates itself; the title bar and the window's measured height do
    /// not (`SettingsWindowController.languageDidChange` has the same note).
    func languageDidChange() {
        guard let window else { return }
        window.title = L.s("About Pluck")
        Task { @MainActor in
            guard let hosting = window.contentView else { return }
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
        }
    }

    private func make() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L.s("About Pluck")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: AboutView())
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        return window
    }
}

struct AboutView: View {
    private var version: String? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap {
            $0.isEmpty ? nil : String(format: L.s("Version %@"), $0)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text(L.s("Pluck"))
                .font(.title2.weight(.semibold))
            if let version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(L.s("Lift subjects out of photos. Offline, free, open source."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                LinkButton(title: L.s("GitHub"), url: AboutWindowController.repository)
                LinkButton(title: L.s("MIT License"), url: AboutWindowController.licence)
            }
            .padding(.top, 4)
            // The one dependency a user could be surprised by: the high-quality model is
            // somebody else's work, and its licence is the reason it is allowed to be here.
            Text(L.s("High-quality matting: BiRefNet (MIT)"))
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        // A floor, not a width. Two bordered buttons side by side are the widest thing in
        // here, and their titles are words — a language whose word for "License" is twice
        // English's would have had them clipped by a hard 320. The window is sized from
        // `fittingSize`, so a wider layout simply makes a wider About panel.
        .frame(minWidth: 320)
    }
}

/// `NSWorkspace` rather than SwiftUI's `Link`: opening a URL is the whole action, and a
/// button says so where a styled `Link` reads as body text that happens to be blue.
private struct LinkButton: View {
    let title: String
    let url: URL

    var body: some View {
        Button(title) { NSWorkspace.shared.open(url) }
            .buttonStyle(.bordered)
            .help(url.absoluteString)
    }
}
