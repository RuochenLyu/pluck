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
        XCTAssertTrue(Preferences(defaults: defaults, service: nil).keepsHistory)
    }

    func testTheChoiceOutlivesTheProcess() {
        Preferences(defaults: defaults, service: nil).keepsHistory = false
        XCTAssertFalse(Preferences(defaults: defaults, service: nil).keepsHistory)
    }

    /// Read per cutout, not cached: flipping the switch has to change where the *next*
    /// drop lands, not where the next launch's drops land.
    func testTheArchiveFollowsThePreferenceImmediately() {
        let preferences = Preferences(defaults: defaults, service: nil)
        XCTAssertEqual(preferences.archive.root, CutoutArchive.history.root)
        preferences.keepsHistory = false
        XCTAssertEqual(preferences.archive.root, CutoutArchive.session.root)
        XCTAssertFalse(preferences.archive.keepsIndex)
    }

    /// Two plain numbers rather than an archived `CGPoint`: a preference nobody can read
    /// with `defaults read` is a preference nobody can debug.
    func testThePreviewCornerRoundTripsAsNumbers() {
        let preferences = Preferences(defaults: defaults, service: nil)
        XCTAssertNil(preferences.previewTopLeft)
        preferences.previewTopLeft = CGPoint(x: 120, y: 800)

        XCTAssertEqual(defaults.double(forKey: "pluck.preview.x"), 120)
        XCTAssertEqual(Preferences(defaults: defaults, service: nil).previewTopLeft, CGPoint(x: 120, y: 800))
    }

    func testClearingThePreviewCornerForgetsItEntirely() {
        let preferences = Preferences(defaults: defaults, service: nil)
        preferences.previewTopLeft = CGPoint(x: 1, y: 2)
        preferences.previewTopLeft = nil
        XCTAssertNil(Preferences(defaults: defaults, service: nil).previewTopLeft)
    }

    /// `SMAppService.mainApp` on a bare `swift build` executable would register a login
    /// item pointing at a build directory. The switch says so instead of doing that.
    func testLaunchAtLoginIsUnavailableWithoutABundle() {
        let preferences = Preferences(defaults: defaults, service: nil)
        XCTAssertFalse(preferences.canLaunchAtLogin)
        XCTAssertFalse(preferences.launchesAtLogin)
    }
}
