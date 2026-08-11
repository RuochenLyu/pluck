import AppKit
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
        static let exportDirectory = "pluck.exportDirectory"
        static let engineID = "pluck.engineID"
        static let languageID = "pluck.languageID"
        static let checksForUpdates = "pluck.checksForUpdates"
        static let appearanceID = "pluck.appearanceID"
        static let showsPreview = "pluck.showsPreview"
        static let layoutID = "pluck.layout"
    }

    /// Whether the preview pane is open. Persisted like Finder persists its preview
    /// column: open by default — a single click then *is* a preview, which is the whole
    /// discoverability answer — and staying however the user last left it.
    var showsPreview: Bool {
        didSet {
            guard showsPreview != oldValue else { return }
            defaults.set(showsPreview, forKey: Key.showsPreview)
        }
    }

    /// How the gallery draws its contents: `"grid"` or `"list"` — Finder's icon and list
    /// views, for the two shapes this window is used in (a handful of pictures to compare;
    /// dozens of files to work through).
    var layoutID: String {
        didSet {
            guard layoutID != oldValue else { return }
            defaults.set(layoutID, forKey: Key.layoutID)
        }
    }

    /// Which appearance the app draws in: `"system"` (default), `"light"` or `"dark"`.
    ///
    /// `NSApp.appearance` is the whole mechanism — nil means "follow the system", and every
    /// semantic colour in the app re-resolves by itself. Applied immediately, like the
    /// language switch and for the same reason: "please relaunch" is a tax, not a design.
    var appearanceID: String {
        didSet {
            guard appearanceID != oldValue else { return }
            defaults.set(appearanceID, forKey: Key.appearanceID)
            applyAppearance()
        }
    }

    /// Pure, so the three legal values — and the fallback for a hand-edited domain — are
    /// testable without an app instance.
    nonisolated static func appearance(for id: String) -> NSAppearance? {
        switch id {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    func applyAppearance() {
        NSApp.appearance = Self.appearance(for: appearanceID)
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
            Key.appearanceID: "system",
            Key.showsPreview: true,
            Key.layoutID: "grid"
        ])
        keepsHistory = defaults.bool(forKey: Key.keepsHistory)
        checksForUpdates = defaults.bool(forKey: Key.checksForUpdates)
        appearanceID = defaults.string(forKey: Key.appearanceID) ?? "system"
        showsPreview = defaults.bool(forKey: Key.showsPreview)
        layoutID = defaults.string(forKey: Key.layoutID) ?? "grid"
        engineID = defaults.string(forKey: Key.engineID) ?? EngineCatalog.defaultEngineID
        languageID = defaults.string(forKey: Key.languageID) ?? L.systemID
        // `didSet` does not run for an assignment in `init`, and this is the launch that has
        // to honour a choice made in a previous one.
        Language.shared.use(languageID)
        if let path = defaults.string(forKey: Key.exportDirectory),
           FileManager.default.fileExists(atPath: path) {
            exportDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    /// The archive new cutouts should be written to. Reading it per cutout rather than
    /// caching it is deliberate: flipping the preference has to take effect on the next
    /// drop, not the next launch.
    var archive: CutoutArchive { keepsHistory ? .history : .session }
}
