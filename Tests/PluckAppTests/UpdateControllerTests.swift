import Foundation
import XCTest

@testable import PluckApp

/// A stand-in for Sparkle's updater, which cannot exist in a test bundle: it refuses to
/// start without a feed URL and a signing key in `Info.plist`, and giving a unit test a fake
/// one would be testing Sparkle rather than the two things that are ours — that the
/// preference reaches the updater, and that a build with no key never gets one.
@MainActor
private final class FakeUpdater: SoftwareUpdating {
    var automaticallyChecksForUpdates = false
    var updateCheckInterval: TimeInterval = 0
    var checks = 0

    func checkForUpdates() { checks += 1 }
}

@MainActor
final class UpdateControllerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "PluckUpdatesTest-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private var configured: [String: Any] {
        [
            UpdateController.feedKey: "https://github.com/RuochenLyu/pluck/releases/latest/download/appcast.xml",
            UpdateController.publicKeyKey: "Yl+3q0eqJXTmZ1z2Yy1Zq3n9Qw5vB0kK7cN2sX8yTfE="
        ]
    }

    // MARK: - What counts as configured

    func testAFeedAndAKeyAreEnough() {
        XCTAssertTrue(UpdateController.isConfigured(configured))
    }

    /// The state every build made before the maintainer runs `generate_keys` is in, and the
    /// state every build from source stays in. It has to be inert rather than broken.
    func testNoPublicKeyMeansNoUpdater() {
        var info = configured
        info.removeValue(forKey: UpdateController.publicKeyKey)
        XCTAssertFalse(UpdateController.isConfigured(info))
        XCTAssertFalse(UpdateController.isConfigured([:]))
        XCTAssertFalse(UpdateController.isConfigured(nil))
    }

    /// The plausible mistake: `Scripts/bundle.sh` substitutes the key into a template, and a
    /// substitution that silently did not match leaves the placeholder behind. An app that
    /// checks every update's signature against the literal string `__SPARKLE_PUBLIC_ED_KEY__`
    /// is indistinguishable, to its user, from one under attack.
    func testTheUnsubstitutedPlaceholderIsNotAKey() {
        var info = configured
        info[UpdateController.publicKeyKey] = "__SPARKLE_PUBLIC_ED_KEY__"
        XCTAssertFalse(UpdateController.isConfigured(info))
        info[UpdateController.publicKeyKey] = ""
        XCTAssertFalse(UpdateController.isConfigured(info))
    }

    /// A feed fetched over plain HTTP is a feed anyone on the path can rewrite. The EdDSA
    /// signature would still catch a forged *package*, but not a downgrade to a real old one.
    func testTheFeedHasToBeHTTPS() {
        var info = configured
        info[UpdateController.feedKey] = "http://example.com/appcast.xml"
        XCTAssertFalse(UpdateController.isConfigured(info))
        info[UpdateController.feedKey] = ""
        XCTAssertFalse(UpdateController.isConfigured(info))
    }

    /// The test bundle has no feed and no key of its own, so the real convenience init has
    /// to land on the inert branch rather than putting Sparkle's "contact the developer"
    /// alert in front of whoever is running the suite.
    func testABundleWithNoSparkleKeysProducesNoUpdater() {
        XCTAssertFalse(UpdateController(bundle: Bundle(for: Self.self)).isAvailable)
    }

    // MARK: - The wiring

    func testLaunchPushesThePreferenceAndTheDailyIntervalIntoTheUpdater() {
        let updater = FakeUpdater()
        let controller = UpdateController(updater: updater)
        XCTAssertTrue(controller.isAvailable)

        controller.adopt(Preferences(defaults: defaults))
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        XCTAssertEqual(updater.updateCheckInterval, 86_400)
    }

    /// The switch has to be honoured at launch, not just while the window is open: a user
    /// who turned it off last month must not be checked on this morning.
    func testAPreferenceTurnedOffLastLaunchKeepsTheUpdaterQuiet() {
        Preferences(defaults: defaults).checksForUpdates = false

        let updater = FakeUpdater()
        updater.automaticallyChecksForUpdates = true
        UpdateController(updater: updater).adopt(Preferences(defaults: defaults))

        XCTAssertFalse(updater.automaticallyChecksForUpdates)
    }

    /// And immediately when it is flipped, which is what Settings calls. "Off at the next
    /// launch" is not what a switch labelled "check automatically" promises.
    func testFlippingTheSwitchReachesTheUpdaterAtOnce() {
        let updater = FakeUpdater()
        let controller = UpdateController(updater: updater)
        controller.adopt(Preferences(defaults: defaults))

        controller.setAutomaticChecks(false)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertFalse(controller.checksAutomatically)

        controller.setAutomaticChecks(true)
        XCTAssertTrue(controller.checksAutomatically)
    }

    /// Every control in an unconfigured build is disabled, but nothing stops a stray call —
    /// and the answer to one has to be silence, not a crash.
    func testAnInertControllerAnswersEverythingWithNothing() {
        let controller = UpdateController(updater: nil)
        XCTAssertFalse(controller.isAvailable)
        XCTAssertFalse(controller.checksAutomatically)
        controller.adopt(Preferences(defaults: defaults))
        controller.setAutomaticChecks(true)
        controller.checkNow()
        XCTAssertFalse(controller.checksAutomatically)
    }

    // MARK: - Version

    func testTheVersionComesFromTheBundleAndIsNilWhenThereIsNone() {
        XCTAssertNil(AppVersion.short(Bundle(for: Self.self)))
        XCTAssertNil(AppVersion.display(Bundle(for: Self.self)))
    }
}
