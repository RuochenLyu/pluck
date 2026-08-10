import XCTest

@testable import PluckApp

@MainActor
final class PreferencesTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "PluckPrefsTest-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// On by default. The grid is the app's only memory of what it has done, and an empty
    /// one on every launch makes the work feel disposable — the bytes are on this Mac
    /// either way, which is the part the privacy promise is actually about.
    func testHistoryIsOnUntilTheUserSaysOtherwise() {
        XCTAssertTrue(Preferences(defaults: defaults).keepsHistory)
    }

    func testTheChoiceOutlivesTheProcess() {
        Preferences(defaults: defaults).keepsHistory = false
        XCTAssertFalse(Preferences(defaults: defaults).keepsHistory)
    }

    /// Read per cutout, not cached: flipping the switch has to change where the *next*
    /// drop lands, not where the next launch's drops land.
    func testTheArchiveFollowsThePreferenceImmediately() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.archive.root, CutoutArchive.history.root)
        preferences.keepsHistory = false
        XCTAssertEqual(preferences.archive.root, CutoutArchive.session.root)
        XCTAssertFalse(preferences.archive.keepsIndex)
    }

    /// On by default, which is the one deliberate exception to "no network unless asked"
    /// (decisions.md 2026-07-28). Asserted rather than assumed, because the argument for
    /// defaulting it on is a security argument and a silent flip to off would be a silent
    /// decision to stop shipping fixes to anyone.
    func testUpdateChecksAreOnUntilTheUserSaysOtherwise() {
        XCTAssertTrue(Preferences(defaults: defaults).checksForUpdates)
    }

    func testTurningUpdateChecksOffOutlivesTheProcess() {
        Preferences(defaults: defaults).checksForUpdates = false
        XCTAssertFalse(Preferences(defaults: defaults).checksForUpdates)
        // Written under a name a human can find. `defaults read com.aix4u.pluck` is the only
        // way anyone can audit from outside the app that the daily request is really off.
        XCTAssertFalse(defaults.bool(forKey: "pluck.checksForUpdates"))
    }

}
