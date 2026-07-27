import AppKit
import SwiftUI

/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: the status item must itself be a
/// drop target (product-plan §4.3), and `MenuBarExtra` hands out no view to register
/// dragged types on. Everything below the status item is still SwiftUI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var dropView: StatusItemDropView?
    private var pluckSignalSource: (any DispatchSourceSignal)?
    private var pasteMonitor: Any?
    private let preview = PreviewPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installPopover()
        installPasteMonitor()
        model.onFeedbackChange = { [weak self] feedback in self?.apply(feedback) }
        model.onPreviewRequest = { [weak self] item in
            guard let self else { return }
            preview.show(item: item, model: model)
        }
        installPluckSignal()
    }

    /// SIGUSR1 triggers the same clipboard pluck as ⌘V in the popover. Exists so the full
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

    /// ⌘V is scoped to the open popover rather than being a global hot key (decisions.md
    /// 2026-07-27). A local monitor sees the event before the responder chain turns it into
    /// a key equivalent, so it fires whatever SwiftUI happens to have focused; the guards
    /// keep it from stealing ⌘V from any other window of ours (the save panel, say).
    private func installPasteMonitor() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // `NSEvent` is not Sendable, so the isolated hop returns a verdict, not the event.
            let handled = MainActor.assumeIsolated { self?.handlePaste(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handlePaste(_ event: NSEvent) -> Bool {
        guard let popover, popover.isShown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              event.window === popover.contentViewController?.view.window
        else { return false }
        model.pluckClipboard()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
            self.pasteMonitor = nil
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.image = StatusIcon.idle

        let drop = StatusItemDropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onClick = { [weak self] in self?.togglePopover() }
        drop.onDrop = { [weak self] payloads in self?.model.handleDrop(payloads) }
        button.addSubview(drop)

        statusItem = item
        dropView = drop
    }

    private func installPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = PopoverView.size
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                model: model,
                onQuit: { NSApp.terminate(nil) },
                onSettings: { [weak self] in self?.showAbout() }
            )
        )
        self.popover = popover
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showAbout() {
        popover?.performClose(nil)
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
        guard let button = statusItem?.button else { return }
        switch feedback {
        case .idle:
            button.image = StatusIcon.idle
            button.contentTintColor = nil
            button.alphaValue = 1
        case .busy:
            button.image = StatusIcon.idle
            button.contentTintColor = nil
            button.alphaValue = 0.45
        case .success:
            button.image = StatusIcon.done
            button.contentTintColor = .systemGreen
            button.alphaValue = 1
        case .failure:
            button.image = StatusIcon.idle
            button.contentTintColor = .systemRed
            button.alphaValue = 1
        }
    }
}
