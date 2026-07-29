import AppKit
import Foundation
import Sparkle

/// The four things Pluck asks an updater to do, and nothing else.
///
/// It exists so `UpdateController` can be driven by a stand-in: Sparkle's own updater
/// refuses to exist without a feed URL and a public key in `Info.plist`, which a unit test
/// bundle does not have and should not be made to fake. What is worth testing here is the
/// wiring — that the preference reaches the updater, that the interval is a day, that a
/// build with no key ends up inert — and all of that is assertable against a protocol.
///
/// `@MainActor` because everything on the far side of it is: Sparkle's updater drives a
/// window and expects the main thread.
@MainActor
protocol SoftwareUpdating: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
    func checkForUpdates()
}

/// `SPUUpdater` already spells all three the same way; the conformance is the whole adapter.
extension SPUUpdater: SoftwareUpdating {}

/// Pluck's second and last network behaviour (decisions.md 2026-07-28), and the only one
/// that runs without the user asking for it each time.
///
/// The controller is deliberately allowed to be *empty*. Sparkle cannot start without a feed
/// URL and an EdDSA public key in `Info.plist`, and it announces a misconfiguration by
/// putting an alert in front of the user telling them to contact the developer — which is the
/// correct behaviour for a shipped app and the wrong behaviour for every build made before
/// the maintainer generates the key pair. So the plist is checked here first, and a build
/// that cannot verify a signature simply has no updater: `Scripts/bundle.sh` keeps working,
/// the app launches, and the two update controls say plainly that this build cannot check.
///
/// The alternative — shipping a placeholder key — is worse in the one way that matters: an
/// app that *tries* to verify and always fails looks identical, from the outside, to an app
/// under attack.
@MainActor
final class UpdateController {
    /// Once a day. The ADR's number, restated at runtime rather than trusted to the plist,
    /// because `Info.plist` is the default for a preference Sparkle then persists — a user
    /// who once ran a build with a different interval would keep it forever.
    static let dailyInterval: TimeInterval = 86_400

    /// `nonisolated` so `isConfigured` stays a pure function anyone can call — it answers a
    /// question about a dictionary, and being able to ask it from a test without hopping to
    /// the main actor is most of why it is separate from the initialiser at all.
    nonisolated static let feedKey = "SUFeedURL"
    nonisolated static let publicKeyKey = "SUPublicEDKey"

    /// Retained for its lifetime, not its members: the standard controller owns the user
    /// driver (the windows Sparkle shows), and letting it go would take the UI with it.
    private let sparkle: SPUStandardUpdaterController?
    private let updater: (any SoftwareUpdating)?

    /// False in every build made before the signing key exists, and in `swift run` shells.
    /// Settings reads it to disable its two controls rather than hide them — "this build
    /// cannot check for updates" is information; a section that silently vanishes is not.
    var isAvailable: Bool { updater != nil }

    init(updater: (any SoftwareUpdating)?) {
        self.sparkle = nil
        self.updater = updater
    }

    convenience init(bundle: Bundle = .main) {
        guard Self.isConfigured(bundle.infoDictionary) else {
            self.init(updater: nil)
            return
        }
        // `startingUpdater: true` is safe now: the check above is exactly the configuration
        // Sparkle would have complained about.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.init(controller: controller)
    }

    private init(controller: SPUStandardUpdaterController) {
        self.sparkle = controller
        self.updater = controller.updater
    }

    /// Whether this bundle carries both halves of the trust chain.
    ///
    /// Pure and taking the dictionary, so the three cases — configured, no key at all, and
    /// the template's placeholder shipped unsubstituted — are testable without building an
    /// .app. The placeholder case is checked because it is the plausible mistake: a
    /// `sed` that did not match leaves `__SPARKLE_PUBLIC_ED_KEY__` in the plist, and an app
    /// that verifies every update against a literal underscore is not better off than one
    /// that does not check at all.
    nonisolated static func isConfigured(_ info: [String: Any]?) -> Bool {
        guard let feed = info?[feedKey] as? String, feed.hasPrefix("https://") else { return false }
        guard let key = info?[publicKeyKey] as? String, !key.isEmpty, !key.hasPrefix("__") else {
            return false
        }
        return true
    }

    /// Called once at launch. The preference is the truth and Sparkle's own
    /// `SUEnableAutomaticChecks` default is a copy of it: two stores for one boolean is one
    /// too many, and the one the user can find in Settings is the one that should win.
    func adopt(_ preferences: Preferences) {
        updater?.updateCheckInterval = Self.dailyInterval
        updater?.automaticallyChecksForUpdates = preferences.checksForUpdates
    }

    /// The other direction, for the Settings switch. Flipping it off has to stop the daily
    /// request now, not at the next launch — that is the whole promise the switch makes.
    func setAutomaticChecks(_ on: Bool) {
        updater?.automaticallyChecksForUpdates = on
    }

    var checksAutomatically: Bool { updater?.automaticallyChecksForUpdates ?? false }

    /// An explicit check, from the status menu or from Settings. `NSApp.activate()` first
    /// because Pluck is an accessory app: Sparkle's window would otherwise open behind
    /// whatever the user is looking at, and there is no Dock icon to click to find it.
    func checkNow() {
        guard let updater else { return }
        NSApp.activate()
        updater.checkForUpdates()
    }
}

/// What this build calls itself, in one place.
///
/// Two surfaces show it — About, and the Updates section that lets the user go looking for a
/// newer one — and the second is the one where a wrong or absent answer matters, because it
/// is read next to a button that goes and compares it against a server.
enum AppVersion {
    /// Nil when there is no version to state, which is a `swift run` shell: the executable
    /// has no `Info.plist` of its own, and inventing "1.0" there would be a lie told to the
    /// one audience that is definitely reading it closely.
    static func short(_ bundle: Bundle = .main) -> String? {
        guard let value = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    static func display(_ bundle: Bundle = .main) -> String? {
        short(bundle).map { String(format: L.s("Version %@"), $0) }
    }
}
