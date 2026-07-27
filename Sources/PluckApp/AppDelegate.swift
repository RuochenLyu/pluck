import AppKit
import SwiftUI

/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: the status item must itself be a
/// drop target (product-plan §4.3), and `MenuBarExtra` hands out no view to register
/// dragged types on. Everything below the status item is still SwiftUI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var dropView: StatusItemDropView?
    private var pluckSignalSource: (any DispatchSourceSignal)?
    private var monitors: [Any] = []
    private let shelf = ShelfPanelController()
    private let preview = PreviewPanelController()

    /// Set when a click already dismissed the shelf, so the status item's own `mouseDown`
    /// does not turn around and reopen what that same click just closed.
    private var swallowIconClick = false
    private var dropTargeted = false

    private static let pulseKey = "pluck.busy.pulse"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installShelf()
        installKeyMonitor()
        installDismissMonitors()
        model.onFeedbackChange = { [weak self] feedback in self?.apply(feedback) }
        model.onPreviewRequest = { [weak self] item in
            guard let self else { return }
            preview.show(item: item, model: model)
        }
        installPluckSignal()
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
    /// ⌘W rides along because a borderless panel has no close button, and
    /// `performClose(_:)` on a window without one just beeps.
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
        if window != nil && !isStatusItem { return }
        shelf.close()
        swallowIconClick = isStatusItem
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard shelf.isVisible,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.window === shelf.panel
        else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
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
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.image = StatusIcon.idle

        let drop = StatusItemDropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onClick = { [weak self] in self?.iconClicked() }
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
                onQuit: { NSApp.terminate(nil) },
                onSettings: { [weak self] in self?.showAbout() }
            )
        )
    }

    /// Opening only. Closing is the dismiss monitor's job, and it has already run for this
    /// same click — a toggle here would fight it.
    private func iconClicked() {
        guard !swallowIconClick else {
            swallowIconClick = false
            return
        }
        guard let button = statusItem?.button else { return }
        shelf.show(from: button)
    }

    /// Dropping on the icon is the primary way in, so the shelf opens on release: the
    /// pending cell, and then the result, appear where the user is already looking.
    private func iconReceived(_ payloads: [DroppedPayload]) {
        model.handleDrop(payloads)
        guard let button = statusItem?.button else { return }
        shelf.show(from: button)
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

    private func showAbout() {
        shelf.close()
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: L.s("Pluck"),
            .credits: NSAttributedString(
                string: L.s("lift subjects out of photos. Offline, free, open source."),
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
            )
        ])
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
