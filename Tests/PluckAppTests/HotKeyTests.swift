import Carbon.HIToolbox
import XCTest

@testable import PluckApp

final class HotKeyTests: XCTestCase {
    func testDefaultComboIsOptionCommandB() {
        let combo = HotKeyCombo.pluckClipboard
        XCTAssertEqual(combo.keyCode, UInt32(kVK_ANSI_B))
        XCTAssertEqual(combo.carbonModifiers, UInt32(optionKey | cmdKey))
        XCTAssertEqual(combo.carbonModifiers & UInt32(shiftKey), 0)
        XCTAssertEqual(combo.carbonModifiers & UInt32(controlKey), 0)
    }

    func testDisplayStringMatchesTheCopyInThePopover() {
        XCTAssertEqual(HotKeyCombo.pluckClipboard.displayString, "⌥⌘B")
    }

    func testSignatureIsFourCharCodePlck() {
        let signature = HotKeyCombo.signature
        let characters = (0..<4).map { Character(UnicodeScalar(UInt8((signature >> (8 * (3 - $0))) & 0xFF))) }
        XCTAssertEqual(String(characters), "plck")
    }
}
