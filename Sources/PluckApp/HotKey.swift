import AppKit
import Carbon.HIToolbox
import Foundation

/// A Carbon hot key description. Carbon's `RegisterEventHotKey` is used rather than
/// `NSEvent.addGlobalMonitorForEvents` on purpose: the monitor route needs Accessibility
/// permission, which is an absurd ask for "remove a background from my clipboard".
struct HotKeyCombo: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// ⌥⌘B — the documented default in product-plan §4.3.
    static let pluckClipboard = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_B),
        carbonModifiers: UInt32(optionKey | cmdKey)
    )

    /// Four-char signature Carbon uses to namespace hot key ids: 'plck'.
    static let signature: OSType = 0x706C_636B

    var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "?")
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_B): "B"
    ]
}

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?
    private var action: (() -> Void)?

    private init() {}

    @discardableResult
    func register(_ combo: HotKeyCombo, action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        if handler == nil {
            InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 1, &spec, nil, &handler)
        }

        let id = EventHotKeyID(signature: HotKeyCombo.signature, id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &registration
        )
        return status == noErr
    }

    func unregister() {
        if let registration {
            UnregisterEventHotKey(registration)
            self.registration = nil
        }
        action = nil
    }

    fileprivate func fire() {
        action?()
    }
}

/// C callbacks cannot capture, so the trampoline goes through the main-actor singleton.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr, id.signature == HotKeyCombo.signature else { return OSStatus(eventNotHandledErr) }
    DispatchQueue.main.async { HotKeyCenter.shared.fire() }
    return noErr
}
