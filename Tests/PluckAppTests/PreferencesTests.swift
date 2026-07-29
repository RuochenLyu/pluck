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

    /// Two plain numbers rather than an archived `CGPoint`: a preference nobody can read
    /// with `defaults read` is a preference nobody can debug.
    func testThePreviewCornerRoundTripsAsNumbers() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertNil(preferences.previewTopLeft)
        preferences.previewTopLeft = CGPoint(x: 120, y: 800)

        XCTAssertEqual(defaults.double(forKey: "pluck.preview.x"), 120)
        XCTAssertEqual(Preferences(defaults: defaults).previewTopLeft, CGPoint(x: 120, y: 800))
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

    /// The default shape of the app: a Dock icon *and* a menu bar icon (decisions.md
    /// 2026-07-29). Asserted because it is the product decision, not a layout detail — a
    /// silent flip back to accessory would be a silent re-decision of what Pluck is.
    func testPluckStartsAsADockAppWithAMenuBarIcon() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.showsMenuBarIcon)
        XCTAssertFalse(preferences.hidesDockIcon)
        XCTAssertEqual(
            AppDelegate.activationPolicy(showsMenuBarIcon: true, hidesDockIcon: false),
            .regular
        )
    }

    /// The only combination that is `.accessory` — which is the shape Pluck used to ship as.
    func testHidingTheDockIconIsTheAccessoryShape() {
        XCTAssertEqual(
            AppDelegate.activationPolicy(showsMenuBarIcon: true, hidesDockIcon: true),
            .accessory
        )
    }

    /// The state that must not be reachable: no status item and no Dock icon leaves nothing
    /// on screen to click. The policy function refuses it even if the booleans arrive that
    /// way, and `Preferences` makes sure they cannot.
    func testTurningOffTheMenuBarIconBringsTheDockIconBack() {
        let preferences = Preferences(defaults: defaults)
        preferences.hidesDockIcon = true
        preferences.showsMenuBarIcon = false

        XCTAssertFalse(preferences.hidesDockIcon)
        XCTAssertFalse(preferences.canHideDockIcon)
        XCTAssertEqual(
            AppDelegate.activationPolicy(showsMenuBarIcon: false, hidesDockIcon: true),
            .regular
        )
    }

    /// A defaults domain someone edited by hand, or one written by a build whose invariant
    /// was different. Read back through the same rule the setter enforces.
    func testAnImpossibleCombinationOnDiskIsRepairedOnRead() {
        defaults.set(false, forKey: "pluck.showsMenuBarIcon")
        defaults.set(true, forKey: "pluck.hidesDockIcon")
        XCTAssertFalse(Preferences(defaults: defaults).hidesDockIcon)
        // And repaired on disk, not only in memory: left there, switching the menu bar icon
        // back on in a later launch would silently hide the Dock icon on the strength of a
        // choice this launch already overruled.
        XCTAssertFalse(defaults.bool(forKey: "pluck.hidesDockIcon"))
    }

    func testThePresenceChoicesOutliveTheProcess() {
        let preferences = Preferences(defaults: defaults)
        preferences.hidesDockIcon = true
        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.showsMenuBarIcon)
        XCTAssertTrue(reloaded.hidesDockIcon)
    }

    func testClearingThePreviewCornerForgetsItEntirely() {
        let preferences = Preferences(defaults: defaults)
        preferences.previewTopLeft = CGPoint(x: 1, y: 2)
        preferences.previewTopLeft = nil
        XCTAssertNil(Preferences(defaults: defaults).previewTopLeft)
    }

}
