import AppKit
import XCTest

@testable import PluckApp

/// Grid shortcuts are decided by one boolean expression in
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

    /// The app menu, asserted by shape: About first, then the update check when the build
    /// carries a signing key, then Settings, then Quit — the standard order, so the one
    /// place a user looks for these is the place they are.
    @MainActor
    func testTheAppMenuCarriesAboutSettingsAndQuit() {
        let menu = AppDelegate.makeMainMenu(target: nil)
        let app = menu.items.first?.submenu
        XCTAssertEqual(
            app?.items.map(\.title),
            [L.s("About Pluck"), "", L.s("Settings…"), "", L.s("Quit Pluck")]
        )
        XCTAssertEqual(app?.items.last?.keyEquivalent, "q")
        XCTAssertEqual(app?.items.last?.action, #selector(NSApplication.terminate(_:)))
    }

    /// Under About, where every Mac app keeps it.
    @MainActor
    func testCheckForUpdatesSitsUnderAboutWhenTheBuildCanCheck() {
        let menu = AppDelegate.makeMainMenu(target: nil, offeringUpdates: true)
        let titles = menu.items.first?.submenu?.items.map(\.title)
        XCTAssertEqual(titles?.prefix(2), [L.s("About Pluck"), L.s("Check for Updates…")])
    }

    /// Omitted rather than greyed in a build with no signing key: a greyed item is a
    /// question the user cannot act on, and Settings says why in a sentence.
    @MainActor
    func testABuildThatCannotUpdateDoesNotOfferTo() {
        let menu = AppDelegate.makeMainMenu(target: nil, offeringUpdates: false)
        let titles = menu.items.first?.submenu?.items.map(\.title) ?? []
        XCTAssertFalse(titles.contains(L.s("Check for Updates…")))
    }

    /// Esc carries no chord, so it gets its own predicate — with the same three flags
    /// forgiven, or clearing the gallery's selection would be the next thing Caps Lock broke.
    func testEscapeIsUnmodifiedEvenUnderTheFlagsNobodyTypesOnPurpose() {
        XCTAssertTrue(AppDelegate.isUnmodified([]))
        XCTAssertTrue(AppDelegate.isUnmodified([.capsLock, .function, .numericPad]))
        XCTAssertFalse(AppDelegate.isUnmodified([.command]))
        XCTAssertFalse(AppDelegate.isUnmodified([.shift]))
    }

    func testNoCommandIsNotACommandShortcut() {
        XCTAssertFalse(AppDelegate.isCommandOnly([]))
        XCTAssertFalse(AppDelegate.isCommandOnly([.capsLock]))
        XCTAssertFalse(AppDelegate.isCommandOnly([.control]))
    }
}
