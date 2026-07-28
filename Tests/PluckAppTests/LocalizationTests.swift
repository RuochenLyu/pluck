import Foundation
import XCTest

@testable import PluckApp

/// Where a lookup is sent, and what happens when the answer is "nowhere".
///
/// `L.Route.resolve` takes its base bundle so the three cases can be built out of a
/// directory instead of out of whatever localizations this machine's app happens to carry.
final class LanguageRouteTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluck-lproj-\(UUID().uuidString)", isDirectory: true)
        let lproj = root.appendingPathComponent("zh-Hans.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try #""Drop images here" = "把图片拖到这里";"#
            .write(to: lproj.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var base: Bundle {
        get throws { try XCTUnwrap(Bundle(path: root.path)) }
    }

    func testFollowingTheSystemLooksInTheAppsOwnBundle() throws {
        let route = L.Route.resolve(L.systemID, in: try base)
        XCTAssertEqual(route.bundle, try base)
        // No locale of ours: whatever the system decided about plurals stands.
        XCTAssertNil(route.locale)
    }

    func testChoosingALanguageRoutesToItsLproj() throws {
        let route = L.Route.resolve("zh-Hans", in: try base)
        XCTAssertNotEqual(route.bundle, try base)
        XCTAssertTrue(route.bundle.bundlePath.hasSuffix("zh-Hans.lproj"))
        // Plurals are chosen by locale, not by which file the strings came out of.
        XCTAssertEqual(route.locale?.identifier, "zh-Hans")
        XCTAssertEqual(
            String(localized: "Drop images here", bundle: route.bundle, locale: route.locale ?? .current),
            "把图片拖到这里"
        )
    }

    /// A language dropped from a later build, or a value written into defaults by hand. It
    /// falls back to the system rather than to a bundle with nothing in it — the failure
    /// mode of the latter is every sentence in the app rendering as its raw key.
    func testAnUnsatisfiableIDFallsBackToTheSystem() throws {
        let route = L.Route.resolve("kl-GL", in: try base)
        XCTAssertEqual(route.bundle, try base)
        XCTAssertNil(route.locale)
    }

    /// English is a real localization the bundle carries, so it is not the fallback path —
    /// but it is also not present in this fixture, and the fallback must still be the base
    /// bundle rather than a crash.
    func testAMissingButValidLanguageIsStillJustTheFallback() throws {
        XCTAssertEqual(L.Route.resolve("en", in: try base).bundle, try base)
    }
}

@MainActor
final class LanguageSwitchTests: XCTestCase {
    /// AppKit surfaces that were built once — the main menu, window titles, the status
    /// item's accessibility label — cannot observe anything, so the notification is the
    /// only thing telling them to rebuild. If it stops being posted they stay in the old
    /// language, and nothing else in the app looks wrong.
    func testSwitchingAnnouncesItself() {
        let language = Language()
        var announcements = 0
        let token = NotificationCenter.default.addObserver(
            forName: .pluckLanguageDidChange,
            object: language,
            queue: nil
        ) { _ in announcements += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        language.use("zh-Hans")
        XCTAssertEqual(language.id, "zh-Hans")
        XCTAssertEqual(announcements, 1)

        // Idempotent: `Preferences` calls this on every launch, and a launch that changed
        // nothing must not send every menu in the app off to rebuild itself.
        language.use("zh-Hans")
        XCTAssertEqual(announcements, 1)

        language.use(L.systemID)
        XCTAssertEqual(announcements, 2)
    }
}
