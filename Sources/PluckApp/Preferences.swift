import Foundation
import Observation
import ServiceManagement

/// Everything the app remembers about how the user wants it to behave. Small on purpose:
/// each entry here is a promise to keep honouring a choice across launches, and an app
/// with no preferences is easier to trust than one with a screen full of them.
///
/// Backed by `UserDefaults` rather than a file of our own — these are booleans and a
/// point, not user data, and the system already has the right place for them.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let keepsHistory = "pluck.keepsHistory"
        static let previewOriginX = "pluck.preview.x"
        static let previewOriginY = "pluck.preview.y"
    }

    /// Whether finished cutouts survive a quit. On by default: the grid is the app's only
    /// memory of what it has done, and an empty one on every launch makes the work feel
    /// disposable. Off means they go to `<tmp>` instead and the launch sweep takes them.
    var keepsHistory: Bool {
        didSet {
            guard keepsHistory != oldValue else { return }
            defaults.set(keepsHistory, forKey: Key.keepsHistory)
        }
    }

    /// The corner the user dragged the preview panel to, if they ever did. Stored as two
    /// numbers because `CGPoint` in defaults would be an archived dictionary, and a
    /// preference nobody can read with `defaults read` is a preference nobody can debug.
    var previewTopLeft: CGPoint? {
        didSet {
            guard let point = previewTopLeft else {
                defaults.removeObject(forKey: Key.previewOriginX)
                defaults.removeObject(forKey: Key.previewOriginY)
                return
            }
            defaults.set(Double(point.x), forKey: Key.previewOriginX)
            defaults.set(Double(point.y), forKey: Key.previewOriginY)
        }
    }

    /// Reflects `SMAppService`, which is the only place this actually lives — writing our
    /// own copy would let the two disagree the moment the user removes the login item in
    /// System Settings. The setter reverts on failure so the switch never claims a state
    /// the system did not accept.
    var launchesAtLogin: Bool {
        didSet {
            guard launchesAtLogin != oldValue, let service else { return }
            do {
                try launchesAtLogin ? service.register() : service.unregister()
            } catch {
                loginItemError = error.localizedDescription
                launchesAtLogin = oldValue
                return
            }
            loginItemError = nil
        }
    }

    /// Non-nil when the last attempt to change the login item failed — surfaced in
    /// Settings, because a toggle that snaps back with no explanation is worse than one
    /// that does not exist. The common cause is running an unbundled build: there is no
    /// `.app` for the system to launch.
    private(set) var loginItemError: String?

    private let defaults: UserDefaults
    /// nil in the test suite and in `swift run` builds: `SMAppService.mainApp` on a bare
    /// executable registers a login item pointing at a build directory.
    private let service: SMAppService?

    init(defaults: UserDefaults = .standard, service: SMAppService? = Preferences.bundledService) {
        self.defaults = defaults
        self.service = service
        defaults.register(defaults: [Key.keepsHistory: true])
        keepsHistory = defaults.bool(forKey: Key.keepsHistory)
        launchesAtLogin = service?.status == .enabled
        if defaults.object(forKey: Key.previewOriginX) != nil {
            previewTopLeft = CGPoint(
                x: defaults.double(forKey: Key.previewOriginX),
                y: defaults.double(forKey: Key.previewOriginY)
            )
        }
    }

    private static var bundledService: SMAppService? {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
            ? .mainApp
            : nil
    }

    /// Whether the login-item switch can do anything at all on this build.
    var canLaunchAtLogin: Bool { service != nil }

    /// The archive new cutouts should be written to. Reading it per cutout rather than
    /// caching it is deliberate: flipping the preference has to take effect on the next
    /// drop, not the next launch.
    var archive: CutoutArchive { keepsHistory ? .history : .session }
}
