import Foundation
import Observation
import PluckKit

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
        static let exportDirectory = "pluck.exportDirectory"
        static let engineID = "pluck.engineID"
        static let languageID = "pluck.languageID"
        static let checksForUpdates = "pluck.checksForUpdates"
        static let showsMenuBarIcon = "pluck.showsMenuBarIcon"
        static let hidesDockIcon = "pluck.hidesDockIcon"
    }

    /// Whether the status item is installed at all.
    ///
    /// On by default, and no longer the app's identity (decisions.md 2026-07-29): Pluck is a
    /// task processor, so the Dock icon is the front door and the menu bar is the shortcut.
    /// Off removes the status item outright rather than dimming it — a menu-bar app's whole
    /// contract is that the icon is either there or it is not.
    var showsMenuBarIcon: Bool {
        didSet {
            guard showsMenuBarIcon != oldValue else { return }
            defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon)
            // The invariant lives here rather than in the two views that can reach these
            // switches: with no status item and no Dock icon there is nothing left on screen
            // to click, which is the state that took a whole ADR to dig out of last time
            // (decisions.md 2026-07-27, the notched-machine report).
            if !showsMenuBarIcon { hidesDockIcon = false }
            announcePresence()
        }
    }

    /// Whether the Dock icon is suppressed — only meaningful while the menu bar icon is on.
    ///
    /// This is the `.accessory` activation policy under a name that says what the user sees.
    /// It is *not* stored as "activation policy": the policy is a fact about AppKit, and the
    /// two booleans are the two things a person can decide.
    var hidesDockIcon: Bool {
        didSet {
            guard hidesDockIcon != oldValue else { return }
            defaults.set(hidesDockIcon, forKey: Key.hidesDockIcon)
            announcePresence()
        }
    }

    /// Whether the Dock icon switch can be touched at all. False means it is also *off* —
    /// `showsMenuBarIcon`'s `didSet` has already seen to that.
    var canHideDockIcon: Bool { showsMenuBarIcon }

    /// `AppDelegate` owns the status item and the activation policy, and neither is a SwiftUI
    /// view that could observe this object. Same mechanism the language switch uses, for the
    /// same reason: AppKit surfaces built once have to be told.
    private func announcePresence() {
        NotificationCenter.default.post(name: .pluckPresenceDidChange, object: self)
    }

    /// Whether Pluck asks GitHub once a day whether there is a newer version.
    ///
    /// On by default, which is the one place this app spends its offline promise (decisions.md
    /// 2026-07-28). The reasoning is that this is a security mechanism wearing the clothes of
    /// a convenience: the people most likely to leave it off are the people running an offline
    /// tool precisely because they do not want to think about it, and a known-bad old build
    /// costs them far more than one HTTPS request a day. Off is one click away and is total —
    /// `UpdateController` stops the cycle immediately, so there is no request left to make.
    ///
    /// Stored here rather than read out of Sparkle's own `SUEnableAutomaticChecks` default so
    /// there is one answer to "is this on", written in the same vocabulary as every other
    /// preference and readable with `defaults read`. `UpdateController.adopt` pushes it into
    /// Sparkle at launch; nothing pushes back.
    var checksForUpdates: Bool {
        didSet {
            guard checksForUpdates != oldValue else { return }
            defaults.set(checksForUpdates, forKey: Key.checksForUpdates)
        }
    }

    /// Which language the app speaks: `"system"`, or a localization the bundle carries.
    ///
    /// The earlier position was that this switch should not exist — macOS already has one
    /// (System Settings ▸ General ▸ Language & Region ▸ Applications), and a second copy of
    /// a choice the system offers is usually a mistake. It is overruled (decisions.md
    /// 2026-07-28) by the user it was leaving out: someone running an English system who
    /// wants this app in Chinese. That person exists, they are not going to change their
    /// system language for a background-removal utility, and the system's per-app control
    /// is three levels down a settings tree most people have never opened.
    ///
    /// Applied at once rather than at next launch — see `Language`. "Please restart" is the
    /// tax the maintainer's objection was really about, and not charging it is what makes
    /// this a switch rather than a second, worse copy of the system's.
    var languageID: String {
        didSet {
            guard languageID != oldValue else { return }
            defaults.set(languageID, forKey: Key.languageID)
            Language.shared.use(languageID)
        }
    }

    /// Which matting engine new work goes through. Apple Vision by default — it is built in,
    /// instant and costs nothing to keep; a downloaded model is something the user went and
    /// asked for, so it is also something they can be assumed to want used.
    ///
    /// Stored as the engine's id rather than as an index or an enum: the list of engines is
    /// the manifest plus what is on disk, and neither is fixed at compile time. An id whose
    /// model has since been deleted resolves back to Vision at use time (`EngineProvider`)
    /// rather than being scrubbed here — a preference that quietly rewrites itself is worse
    /// than one that is briefly unsatisfiable.
    var engineID: String {
        didSet {
            guard engineID != oldValue else { return }
            defaults.set(engineID, forKey: Key.engineID)
        }
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

    /// Where Export All last put things, so the picker opens there again. A plain path,
    /// not a security-scoped bookmark: Pluck is not sandboxed, and a bookmark would buy
    /// nothing but a blob nobody can read. A folder that has since been deleted or
    /// unmounted reads back as nil rather than sending the panel somewhere that no longer
    /// exists.
    var exportDirectory: URL? {
        didSet {
            guard let directory = exportDirectory else {
                defaults.removeObject(forKey: Key.exportDirectory)
                return
            }
            defaults.set(directory.path, forKey: Key.exportDirectory)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.keepsHistory: true,
            Key.engineID: EngineCatalog.defaultEngineID,
            Key.languageID: L.systemID,
            Key.checksForUpdates: true,
            Key.showsMenuBarIcon: true,
            Key.hidesDockIcon: false
        ])
        keepsHistory = defaults.bool(forKey: Key.keepsHistory)
        checksForUpdates = defaults.bool(forKey: Key.checksForUpdates)
        let menuBar = defaults.bool(forKey: Key.showsMenuBarIcon)
        showsMenuBarIcon = menuBar
        // Read through the same invariant the setter enforces: a defaults domain edited by
        // hand — or written by a build that had a third switch — must not be able to produce
        // an app with no icon anywhere.
        let hidesDock = defaults.bool(forKey: Key.hidesDockIcon) && menuBar
        hidesDockIcon = hidesDock
        // Written back, not just corrected in memory: leaving the impossible value on disk
        // means switching the menu bar icon back on later silently hides the Dock icon
        // again, on the strength of a choice this launch already overruled.
        defaults.set(hidesDock, forKey: Key.hidesDockIcon)
        engineID = defaults.string(forKey: Key.engineID) ?? EngineCatalog.defaultEngineID
        languageID = defaults.string(forKey: Key.languageID) ?? L.systemID
        // `didSet` does not run for an assignment in `init`, and this is the launch that has
        // to honour a choice made in a previous one.
        Language.shared.use(languageID)
        if let path = defaults.string(forKey: Key.exportDirectory),
           FileManager.default.fileExists(atPath: path) {
            exportDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }
        if defaults.object(forKey: Key.previewOriginX) != nil {
            previewTopLeft = CGPoint(
                x: defaults.double(forKey: Key.previewOriginX),
                y: defaults.double(forKey: Key.previewOriginY)
            )
        }
    }

    /// The archive new cutouts should be written to. Reading it per cutout rather than
    /// caching it is deliberate: flipping the preference has to take effect on the next
    /// drop, not the next launch.
    var archive: CutoutArchive { keepsHistory ? .history : .session }
}

extension Notification.Name {
    /// Where Pluck shows up — the Dock icon, the status item — has changed.
    static let pluckPresenceDidChange = Notification.Name("pluck.presenceDidChange")
}
