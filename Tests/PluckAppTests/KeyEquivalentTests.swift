import AppKit
import XCTest

@testable import PluckApp

/// Pluck has no menu bar to show, so its shortcuts are decided by one boolean expression in
/// a local event monitor. That expression used to be an equality test against `.command`,
/// which meant every shortcut in the app — paste, close, all of it — silently stopped
/// working while Caps Lock was on.
final class KeyEquivalentTests: XCTestCase {
    func testPlainCommandIsAccepted() {
        XCTAssertTrue(AppDelegate.isCommandOnly([.command]))
    }

    /// The regression. Caps Lock sets a bit in `deviceIndependentFlagsMask` like any other
    /// modifier, and a user who leaves it on is not asking for different shortcuts.
    func testCapsLockDoesNotBreakACommandShortcut() {
        XCTAssertTrue(AppDelegate.isCommandOnly([.command, .capsLock]))
    }

    /// Fn is set on every key press on a laptop keyboard for keys that carry a second
    /// meaning, and the numeric-pad bit rides along with the arrow keys.
    func testFunctionAndNumericPadAreIgnoredToo() {
        XCTAssertTrue(AppDelegate.isCommandOnly([.command, .function, .numericPad, .capsLock]))
    }

    /// The other half: ⇧⌘V is a different chord, and the monitor swallowing it would take a
    /// shortcut away from whatever window is in front.
    func testChordsWithRealModifiersAreNotCommandOnly() {
        XCTAssertFalse(AppDelegate.isCommandOnly([.command, .shift]))
        XCTAssertFalse(AppDelegate.isCommandOnly([.command, .option]))
        XCTAssertFalse(AppDelegate.isCommandOnly([.command, .control]))
    }

    func testNoCommandIsNotACommandShortcut() {
        XCTAssertFalse(AppDelegate.isCommandOnly([]))
        XCTAssertFalse(AppDelegate.isCommandOnly([.capsLock]))
        XCTAssertFalse(AppDelegate.isCommandOnly([.control]))
    }
}
