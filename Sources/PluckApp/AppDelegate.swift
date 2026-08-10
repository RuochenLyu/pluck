import AppKit
import SwiftUI

/// Pluck is a plain Dock app (decisions.md 2026-08-10). One window, standard chrome; the
/// menu-bar shelf, the status item and the activation-policy switches are gone — the
/// shortcut surfaces had grown into a second UI, and the standard window is the one users
/// already know how to operate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private lazy var model = AppModel(preferences: preferences)
    private var pluckSignalSource: (any DispatchSourceSignal)?
    private var monitors: [Any] = []
    private var observers: [any NSObjectProtocol] = []
    private let settings = SettingsWindowController()
    private let about = AboutWindowController()
    private let mainWindow = MainWindowController()
    private let updates = UpdateController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First, and synchronously: whatever the last run left behind is dead weight, and it
        // is dead weight made of the user's photographs. Synchronous because the alternative
        // races — a detached sweep can land after the first drop has already written into
        // the same directory, and then it deletes a file the grid is pointing at. Nothing
        // that can create one has been installed yet at this line, and `model` has not been
        // touched, so nothing has been restored from the history root either.
        //
        // Both roots when history is off: the preference can be switched off mid-session,
        // and the files that were already written under it have to expire somewhere.
        CutoutArchive.session.discardEverything()
        if !preferences.keepsHistory { CutoutArchive.history.discardEverything() }
        // Before the menu is built: whether "Check for Updates…" exists depends on it.
        updates.adopt(preferences)
        installMainMenu()
        installKeyMonitor()
        installPluckSignal()
        installLanguageObserver()
        mainWindow.onDrop = { [weak self] payloads in self?.model.handleDrop(payloads) }
        mainWindow.onOpenSettings = { [weak self] in self?.showSettings() }
        mainWindow.show(model: model)
    }

    /// Images dropped on the Dock icon, double-clicked in Finder, or handed over by
    /// `open -a Pluck …`. All three arrive here, and all three are the same gesture as a
    /// drop on the window — so they go through the same entry point, in one call, because a
    /// folder full of images opened at once is one batch and not thirty.
    func application(_ application: NSApplication, open urls: [URL]) {
        let payloads = urls.map(DroppedPayload.file)
        guard !payloads.isEmpty else { return }
        model.handleDrop(payloads)
        mainWindow.show(model: model)
    }

    /// Clicking the Dock icon, or launching Pluck again while it is already running: the
    /// ordinary "bring the app back" gesture, and the main window is what it means.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        mainWindow.show(model: model)
        return true
    }

    /// Everything AppKit built once and now keeps.
    ///
    /// SwiftUI needs no help — its bodies ask `L.s` for their sentences and `L.s` subscribes
    /// them (`Localization.swift`). What cannot be subscribed is a menu that was assembled
    /// into `NSApp.mainMenu` or a string handed to `NSWindow.title`: those are copies, and
    /// copies have to be replaced. This is the whole list, and it is short enough to keep
    /// honest.
    private func installLanguageObserver() {
        let token = NotificationCenter.default.addObserver(
            forName: .pluckLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.installMainMenu()
                self.mainWindow.languageDidChange()
                self.settings.languageDidChange()
                self.about.languageDidChange()
            }
        }
        observers.append(token)
    }

    /// The main menu is where AppKit resolves key equivalents: without it the save panel's
    /// filename field has no ⌘A/⌘C/⌘V/⌘Z at all — the standard Edit items are not built
    /// into `NSTextField`, they are menu items that dispatch `cut:`/`copy:`/`paste:` down
    /// the responder chain — and no window could be closed with ⌘W.
    private func installMainMenu() {
        NSApp.mainMenu = Self.makeMainMenu(target: self, offeringUpdates: updates.isAvailable)
    }

    /// Built by a static function so the shape of the menu — what is in it, in what order,
    /// with which shortcut — is assertable without a menu bar to put it in.
    ///
    /// "Check for Updates…" sits under About, which is where every Mac app keeps it. It is
    /// *omitted*, not disabled, when the build has no updater: a greyed item is a question
    /// the user cannot act on, and Settings is where the reason is written down.
    static func makeMainMenu(target: AnyObject?, offeringUpdates: Bool = false) -> NSMenu {
        let main = NSMenu()
        var appItems: [NSMenuItem] = [
            item(L.s("About Pluck"), #selector(showAbout), "", target: target)
        ]
        if offeringUpdates {
            appItems.append(item(L.s("Check for Updates…"), #selector(checkForUpdates), "", target: target))
        }
        appItems.append(contentsOf: [
            .separator(),
            item(L.s("Settings…"), #selector(showSettings), ",", target: target),
            .separator(),
            item(L.s("Quit Pluck"), #selector(NSApplication.terminate(_:)), "q")
        ])
        main.addItem(submenu(L.s("Pluck"), appItems))
        main.addItem(submenu(L.s("File"), [
            item(L.s("Close"), #selector(NSWindow.performClose(_:)), "w")
        ]))
        // Standard and in the standard order, because these are muscle memory: the point is
        // that a text field in one of our panels behaves like a text field anywhere else.
        main.addItem(submenu(L.s("Edit"), [
            item(L.s("Undo"), NSSelectorFromString("undo:"), "z"),
            item(L.s("Redo"), NSSelectorFromString("redo:"), "z", modifiers: [.command, .shift]),
            .separator(),
            item(L.s("Cut"), #selector(NSText.cut(_:)), "x"),
            item(L.s("Copy"), #selector(NSText.copy(_:)), "c"),
            item(L.s("Paste"), #selector(NSText.paste(_:)), "v"),
            item(L.s("Delete"), #selector(NSText.delete(_:)), ""),
            item(L.s("Select All"), #selector(NSText.selectAll(_:)), "a")
        ]))
        return main
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// A nil `target` means the responder chain, which is what makes the Edit items
    /// self-disabling: nothing in a grid full of images answers `paste:`, so the item is
    /// grey there and live in a save panel's name field, with no code of ours deciding it.
    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String,
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    /// SIGUSR1 triggers the same clipboard pluck as ⌘V in the window. Exists so the full
    /// pipeline is drivable without a GUI (headless QA, and `pkill -USR1 PluckApp` as a
    /// scripting hook).
    private func installPluckSignal() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.model.pluckClipboard() }
        }
        source.resume()
        pluckSignalSource = source
    }

    /// ⌘V, ⌘A, Esc and ⌫ in the main window are grid operations, not text operations. A
    /// local monitor sees the event before the responder chain turns it into a key
    /// equivalent; the guards keep it from stealing keys from any other window of ours
    /// (the save panel, say).
    private func installKeyMonitor() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // `NSEvent` is not Sendable, so the isolated hop returns a verdict, not the event.
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
        if let monitor { monitors.append(monitor) }
    }

    /// Whether this is ⌘ and nothing else that matters.
    ///
    /// Equality against `.command` alone was wrong in a way nobody notices until it happens
    /// to them: Caps Lock sets a bit in `deviceIndependentFlagsMask`, so with it on, every
    /// shortcut in this app stopped working. The three flags dropped here are the ones a
    /// user does not think of as part of the chord. `.shift`, `.option` and `.control` are
    /// *not* dropped: ⇧⌘V is a different key stroke, and this monitor must not eat it.
    nonisolated static func isCommandOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad]) == .command
    }

    /// The same question for a key that carries no chord at all — Esc, ⌫. Same three flags
    /// ignored, for the same reason: Caps Lock is not part of a keystroke the user thinks
    /// they are typing.
    nonisolated static func isUnmodified(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad]).isEmpty
    }

    /// Esc and forward-delete have no character to match on; named constants beat
    /// unexplained 53s.
    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51

    private func handleKey(_ event: NSEvent) -> Bool {
        guard mainWindow.owns(event.window) else { return false }
        // Esc clears the gallery's selection, and only when there is one to clear: an Esc
        // that is swallowed while nothing is selected is an Esc that never reaches whatever
        // else might have wanted it.
        if event.keyCode == Self.escapeKeyCode,
           Self.isUnmodified(event.modifierFlags),
           !model.selection.isEmpty {
            model.clearSelection()
            return true
        }
        // ⌫ deletes what is selected — the standard grid gesture, and the keyboard's only
        // route to Delete now that the context menu is the pointer's.
        if event.keyCode == Self.deleteKeyCode,
           Self.isUnmodified(event.modifierFlags),
           !model.selection.isEmpty {
            model.discardSelected()
            return true
        }
        guard Self.isCommandOnly(event.modifierFlags) else { return false }
        // ⌘V never goes through the menu: `paste:` is a *text* operation dispatched to
        // whatever is first responder, and no view in this app implements it; pasting into
        // Pluck means "matte the clipboard", which only the model can do. ⌘A is the same
        // story — selecting in the gallery is the meaning ⌘A has here.
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v":
            model.pluckClipboard()
            return true
        case "a":
            model.selectAll()
            return true
        default:
            return false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    @objc private func showSettings() {
        settings.show(model: model, preferences: preferences, updates: updates)
    }

    @objc private func showAbout() {
        about.show()
    }

    @objc private func checkForUpdates() {
        updates.checkNow()
    }
}
