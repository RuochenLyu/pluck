import AppKit
import SwiftUI

/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: the status item must itself be a
/// drop target (product-plan §4.3), and `MenuBarExtra` hands out no view to register
/// dragged types on. Everything below the status item is still SwiftUI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private lazy var model = AppModel(preferences: preferences)
    private var statusItem: NSStatusItem?
    private var dropView: StatusItemDropView?
    private var pluckSignalSource: (any DispatchSourceSignal)?
    private var monitors: [Any] = []
    private var observers: [any NSObjectProtocol] = []
    private let shelf = ShelfPanelController()
    private lazy var preview = PreviewPanelController(preferences: preferences)
    private let settings = SettingsWindowController()
    private let about = AboutWindowController()
    private let mainWindow = MainWindowController()

    /// Set when a click already dismissed the shelf, so the status item's own `mouseDown`
    /// does not turn around and reopen what that same click just closed.
    private var swallowIconClick = false
    private var dropTargeted = false

    private static let pulseKey = "pluck.busy.pulse"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        installMainMenu()
        installStatusItem()
        installShelf()
        installKeyMonitor()
        installDismissMonitors()
        model.onFeedbackChange = { [weak self] feedback in self?.apply(feedback) }
        model.onPreviewRequest = { [weak self] item in
            guard let self else { return }
            preview.show(item: item, model: model, beside: shelf.isVisible ? shelf.panel?.frame : nil)
        }
        installPluckSignal()
        installLanguageObserver()
        revealIfUnreachable()
    }

    /// Everything AppKit built once and now keeps.
    ///
    /// SwiftUI needs no help — its bodies ask `L.s` for their sentences and `L.s` subscribes
    /// them (`Localization.swift`). What cannot be subscribed is a menu that was assembled
    /// into `NSApp.mainMenu`, a string handed to `NSWindow.title`, or an accessibility label
    /// set on a view once at birth: those are copies, and copies have to be replaced. This is
    /// the whole list, and it is short enough to keep honest.
    ///
    /// The status item's right-click menu is not on it: it is rebuilt for the duration of
    /// each click (`showStatusMenu`), so it is already in whatever language is current.
    private func installLanguageObserver() {
        let token = NotificationCenter.default.addObserver(
            forName: .pluckLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.installMainMenu()
                self.dropView?.relabel()
                self.mainWindow.languageDidChange()
                self.settings.languageDidChange()
                self.about.languageDidChange()
            }
        }
        observers.append(token)
    }

    /// A menu bar an `.accessory` app never draws, and cannot do without.
    ///
    /// The main menu is where AppKit resolves key equivalents, so with `NSApp.mainMenu` nil
    /// the save panel's filename field had no ⌘A/⌘C/⌘V/⌘Z at all — the standard Edit items
    /// are not built into `NSTextField`, they are menu items that dispatch `cut:`/`copy:`/
    /// `paste:` down the responder chain — and no window in the app could be closed with ⌘W
    /// unless `handleKey` below knew about it by name. Nothing here is ever seen: an
    /// accessory app shows no menu bar even when it is frontmost. The titles still go
    /// through the catalog, because "invisible" is a fact about today's activation policy
    /// and not about the strings.
    private func installMainMenu() {
        let main = NSMenu()
        main.addItem(Self.submenu(L.s("Pluck"), [
            Self.item(L.s("About Pluck"), #selector(showAbout), "", target: self),
            Self.item(L.s("Settings…"), #selector(showSettings), ",", target: self),
            .separator(),
            Self.item(L.s("Quit Pluck"), #selector(NSApplication.terminate(_:)), "q")
        ]))
        main.addItem(Self.submenu(L.s("File"), [
            Self.item(L.s("Close"), #selector(NSWindow.performClose(_:)), "w")
        ]))
        // Standard and in the standard order, because these are muscle memory: the point is
        // that a text field in one of our panels behaves like a text field anywhere else.
        main.addItem(Self.submenu(L.s("Edit"), [
            Self.item(L.s("Undo"), NSSelectorFromString("undo:"), "z"),
            Self.item(L.s("Redo"), NSSelectorFromString("redo:"), "z", modifiers: [.command, .shift]),
            .separator(),
            Self.item(L.s("Cut"), #selector(NSText.cut(_:)), "x"),
            Self.item(L.s("Copy"), #selector(NSText.copy(_:)), "c"),
            Self.item(L.s("Paste"), #selector(NSText.paste(_:)), "v"),
            Self.item(L.s("Delete"), #selector(NSText.delete(_:)), ""),
            Self.item(L.s("Select All"), #selector(NSText.selectAll(_:)), "a")
        ]))
        NSApp.mainMenu = main
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// A nil `target` means the responder chain, which is what makes the Edit items
    /// self-disabling: nothing in a shelf full of images answers `paste:`, so the item is
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

    /// SIGUSR1 triggers the same clipboard pluck as ⌘V in the shelf. Exists so the full
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

    /// ⌘V is scoped to the open shelf rather than being a global hot key (decisions.md
    /// 2026-07-27). A local monitor sees the event before the responder chain turns it into
    /// a key equivalent, so it fires whatever SwiftUI happens to have focused; the guards
    /// keep it from stealing ⌘V from any other window of ours (the save panel, say).
    ///
    /// ⌘W rides along for the two borderless panels, for the same reason the File ▸ Close
    /// item cannot serve them: a window with no close button has `performClose(_:)`
    /// disabled by AppKit's menu validation, and calling it anyway just beeps.
    private func installKeyMonitor() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // `NSEvent` is not Sendable, so the isolated hop returns a verdict, not the event.
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
        if let monitor { monitors.append(monitor) }
    }

    /// Click anywhere outside the shelf and it goes away. Mouse monitors need no
    /// Accessibility permission — that requirement is specific to keyboard events.
    ///
    /// Two monitors because they see disjoint worlds: the global one only reports events
    /// delivered to *other* processes, and the local one only ours. The status item counts
    /// as ours, which is how clicking the icon while the shelf is open closes it without a
    /// separate toggle.
    private func installDismissMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissShelf(hitting: nil) }
        })
        if let global { monitors.append(global) }

        let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.dismissShelf(hitting: event.window) }
            return event
        })
        if let local { monitors.append(local) }
    }

    /// `window` is nil when the click landed in another process — the global monitor never
    /// learns which window that was, and does not need to.
    private func dismissShelf(hitting window: NSWindow?) {
        guard shelf.isVisible else { return }
        let isStatusItem = window != nil && window === statusItem?.button?.window
        // A click inside one of our own windows is not a dismissal. That covers the shelf
        // itself and also the preview and save panels, which are opened *from* the shelf —
        // pulling it out from under them would read as a glitch, not as a dismissal.
        //
        // The main window is the exception: it is not an auxiliary of the shelf but the
        // other half of the app, and the shelf floats above every window we own. Leaving it
        // up would park a 340pt panel over the thing the user just clicked on.
        if window != nil && !isStatusItem && !mainWindow.owns(window) { return }
        shelf.close()
        swallowIconClick = isStatusItem
    }

    /// Whether this is ⌘ and nothing else that matters.
    ///
    /// Equality against `.command` alone was wrong in a way nobody notices until it happens
    /// to them: Caps Lock sets a bit in `deviceIndependentFlagsMask`, so with it on, every
    /// shortcut in this app stopped working — ⌘V, ⌘W, all of it. The three flags dropped
    /// here are the ones a user does not think of as part of the chord. `.shift`,
    /// `.option` and `.control` are *not* dropped: ⇧⌘V is a different key stroke, and this
    /// monitor must not eat it.
    ///
    /// Static and pure because the bug was in a boolean expression, and a boolean
    /// expression is testable without an event.
    nonisolated static func isCommandOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad]) == .command
    }

    /// The same question for a key that carries no chord at all — Esc. Same three flags
    /// ignored, for the same reason: Caps Lock is not part of a keystroke the user thinks
    /// they are typing.
    nonisolated static func isUnmodified(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad]).isEmpty
    }

    /// Esc's key code. It has no character to match on — `charactersIgnoringModifiers` is the
    /// escape character itself — and a named constant beats an unexplained 53.
    private static let escapeKeyCode: UInt16 = 53

    private func handleKey(_ event: NSEvent) -> Bool {
        // Esc clears the gallery's selection, and only when there is one to clear: an Esc
        // that is swallowed while nothing is selected is an Esc that never reaches whatever
        // else might have wanted it.
        if mainWindow.owns(event.window),
           event.keyCode == Self.escapeKeyCode,
           Self.isUnmodified(event.modifierFlags),
           !model.selection.isEmpty {
            model.clearSelection()
            return true
        }
        guard Self.isCommandOnly(event.modifierFlags) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased()
        // ⌘V never goes through the menu, on any surface. `paste:` is a *text* operation
        // dispatched to whatever is first responder, and no view in this app implements it;
        // pasting into Pluck means "matte the clipboard", which only the model can do.
        //
        // ⌘W is the other way round wherever AppKit will take it. The main window is a
        // standard titled, closable window, so the File ▸ Close item validates and closes
        // it — that dispatch is gone from here. The two panels are borderless: a window
        // with no close button has `performClose(_:)` disabled by AppKit's own menu
        // validation, so for them this monitor is still the only route.
        if mainWindow.owns(event.window) {
            // ⌘A is Select All in the Edit menu, which dispatches `selectAll:` to the first
            // responder — a *text* operation, and there is no text in this window. Selecting
            // in the gallery is the meaning ⌘A has here, and the monitor is the only place
            // that can claim it before the menu does.
            switch key {
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
        if preview.owns(event.window) {
            guard key == "w" else { return false }
            preview.close()
            return true
        }
        guard shelf.isVisible, event.window === shelf.panel else { return false }
        switch key {
        case "v":
            model.pluckClipboard()
            return true
        case "w":
            shelf.close()
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

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.image = StatusIcon.idle

        let drop = StatusItemDropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onClick = { [weak self] in self?.iconClicked() }
        drop.onSecondaryClick = { [weak self] in self?.showStatusMenu() }
        drop.onDrop = { [weak self] payloads in self?.iconReceived(payloads) }
        drop.onDragTargeted = { [weak self] on in self?.showDropAffordance(on) }
        button.addSubview(drop)

        statusItem = item
        dropView = drop
    }

    private func installShelf() {
        shelf.onDrop = { [weak self] payloads in self?.model.handleDrop(payloads) }
        shelf.install(
            content: ShelfView(
                model: model,
                dropTarget: shelf.dropTarget,
                onSettings: { [weak self] in self?.showSettings() },
                onMainWindow: { [weak self] in self?.showMainWindow() }
            )
        )
        mainWindow.onDrop = { [weak self] payloads in self?.model.handleDrop(payloads) }
    }

    private func showMainWindow() {
        shelf.close()
        mainWindow.show(model: model)
    }

    /// Opening only. Closing is the dismiss monitor's job, and it has already run for this
    /// same click — a toggle here would fight it.
    private func iconClicked() {
        guard !swallowIconClick else {
            swallowIconClick = false
            return
        }
        openShelf()
    }

    /// Left button opens the shelf, right button opens a menu: the pattern every menu-bar
    /// app on this machine follows, and the reason About and Quit no longer need a pull-down
    /// inside the shelf. Only the two the shelf cannot hold — Settings has a gear of its own
    /// there, and repeating it here would be a third route to one window.
    ///
    /// `statusItem.menu` is set for the duration of the click and cleared after: assigning it
    /// permanently would make AppKit swallow the *left* click too, and the shelf would become
    /// unreachable.
    private func showStatusMenu() {
        // The dismiss monitor has already closed the shelf for this same right click and
        // armed the swallow, which would otherwise eat the next left click on the icon.
        swallowIconClick = false
        guard let item = statusItem, let button = item.button else { return }
        item.menu = Self.makeStatusMenu(target: self)
        button.performClick(nil)
        item.menu = nil
    }

    /// Built by a static function so the shape of the menu — what is in it, in what order,
    /// with which shortcut — is assertable without a menu bar to put it in.
    static func makeStatusMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(L.s("About Pluck"), #selector(showAbout), "", target: target))
        menu.addItem(.separator())
        menu.addItem(item(L.s("Quit Pluck"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    /// Dropping on the icon is the primary way in, so the shelf opens on release: the
    /// pending cell, and then the result, appear where the user is already looking.
    private func iconReceived(_ payloads: [DroppedPayload]) {
        model.handleDrop(payloads)
        openShelf()
    }

    private func openShelf() {
        let anchor = statusAnchor()
        shelf.show(anchor: anchor?.rect, on: anchor?.screen)
    }

    /// The status item's rect in screen coordinates, or nil when the pointer could not
    /// actually get to it.
    ///
    /// A menu bar with no room left still hands back a button; it just parks it off the end
    /// of the bar or under the camera housing. With no Dock icon and no window, an app in
    /// that state has no surface at all — reported 2026-07-27 on a notched machine — so
    /// every path that opens the shelf has to have an answer for "and if there is no icon?".
    private func statusAnchor() -> (rect: NSRect, screen: NSScreen)? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard rect.width > 1,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
        else { return nil }
        // The two auxiliary areas are the stretches of the menu bar row the notch leaves
        // exposed. Touching neither means sitting behind it.
        let exposed = [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 }
        guard exposed.isEmpty || exposed.contains(where: { $0.intersects(rect) }) else { return nil }
        return (rect, screen)
    }

    /// Launching Pluck again while it is already running is the way back in. LaunchServices
    /// sends this rather than starting a second copy, and for an app with no Dock icon it is
    /// the only gesture a user can perform that we are guaranteed to receive.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openShelf()
        return true
    }

    /// The status item does not reach its final position until the bar has laid out, so this
    /// asks once that has had a chance to happen. Opening the shelf is not a nicety here: an
    /// app that is invisible *and* silent on launch is indistinguishable from one that
    /// failed to start, and there would be nothing on screen to click to find out.
    private func revealIfUnreachable() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard statusAnchor() == nil, !shelf.isVisible else { return }
            openShelf()
        }
    }

    /// Filled ghost plus coral tint while a droppable image is overhead — the icon is the
    /// only surface available to say "yes, this one".
    private func showDropAffordance(_ on: Bool) {
        dropTargeted = on
        guard let button = statusItem?.button else { return }
        if on {
            pulse(false)
            button.image = StatusIcon.done
            button.contentTintColor = Palette.coralNS
        } else {
            apply(model.feedback)
        }
    }

    /// Closes the shelf on the way, like About does: the shelf dismisses on any click
    /// outside itself, and a window opening behind a panel that is about to vanish reads
    /// as a glitch.
    @objc private func showSettings() {
        shelf.close()
        settings.show(model: model, preferences: preferences)
    }

    @objc private func showAbout() {
        shelf.close()
        about.show()
    }

    private func apply(_ feedback: StatusFeedback) {
        // A drag hovering over the icon owns it until it leaves; `showDropAffordance`
        // replays whatever state was current once it does.
        guard !dropTargeted, let button = statusItem?.button else { return }
        pulse(feedback == .busy)
        switch feedback {
        case .idle, .busy:
            button.image = StatusIcon.idle
            button.contentTintColor = nil
        case .success:
            button.image = StatusIcon.done
            button.contentTintColor = .systemGreen
        case .failure:
            button.image = StatusIcon.idle
            button.contentTintColor = .systemRed
        }
        button.alphaValue = 1
    }

    /// Breathing pulse while work is in flight — the only progress signal left when the
    /// shelf is closed (the drag-onto-the-icon path). Idempotent: re-entering `.busy`
    /// while already pulsing must not restack the animation and double the opacity swing.
    private func pulse(_ on: Bool) {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        guard on else {
            layer.removeAnimation(forKey: Self.pulseKey)
            return
        }
        guard layer.animation(forKey: Self.pulseKey) == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.45
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: Self.pulseKey)
    }
}
