import AppKit
import SwiftUI

/// The first surface in Pluck with a system title bar, and deliberately so: §4.7's
/// borderless-glass rules are about panels that hang off the menu bar and stand in front
/// of the user's work. Settings is a window the user goes looking for, opens once, and
/// closes — it should look like every other Settings window on the machine.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(model: AppModel, preferences: Preferences) {
        if window == nil {
            let window = make(model: model, preferences: preferences)
            // Centred once, at birth. Re-centring on every open would undo the user's own
            // placement, which is the one thing a window that is opened repeatedly must not do.
            window.center()
            self.window = window
        }
        // An accessory app is not frontmost by default, so both halves are needed: activate
        // the process, then raise the window inside it.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func make(model: AppModel, preferences: Preferences) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L.s("Pluck Settings")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SettingsView(model: model, preferences: preferences))
        window.contentView = hosting
        // The pane's height is whatever three sections of text come to; guessing it in the
        // contentRect above would either clip the offline statement or leave a gap under it.
        window.setContentSize(hosting.fittingSize)
        return window
    }
}

/// One pane, three rows. The tabbed toolbar §4.7 calls for arrives with the models pane in
/// v0.3; tabs over a single pane are chrome for its own sake.
struct SettingsView: View {
    let model: AppModel
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Toggle(L.s("Keep recent cutouts between launches"), isOn: $preferences.keepsHistory)
                        .onChange(of: preferences.keepsHistory) { _, keeps in
                            guard !keeps else { return }
                            model.forgetStoredHistory()
                        }
                    Text(L.s("Stored on this Mac in Application Support, and never uploaded. Turn this off and cutouts are kept only until you quit."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L.s("Clear recent cutouts")) { model.clearRecents() }
                        .disabled(model.recents.items.isEmpty)
                } header: {
                    Text(L.s("History")).font(.headline)
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            // Not a boast — it is the one claim the whole product rests on, and the place a
            // doubting user looks first is Settings. Out of the grouped box it used to sit
            // in: a boxed row reads as a setting, and this is a statement about the app.
            Text(L.s("Pluck works entirely offline. It makes no network requests and has no account, no telemetry and no uploads."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
