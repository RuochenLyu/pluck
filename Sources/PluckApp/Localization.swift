import Foundation
import Observation

/// Every user-visible string goes through here so the String Catalog stays the single
/// source of copy. Bare literals in views are a build-review failure, not a style nit.
///
/// Keys are the English copy itself, so a missed lookup still renders correct English —
/// which is exactly why the packaging step has to be verified rather than trusted, and
/// also what makes a half-translated language safe to ship: an untranslated key falls
/// through to a correct English sentence rather than to `some.dotted.identifier`.
enum L {
    /// The value of `Preferences.languageID` that means "whatever the system says".
    static let systemID = "system"

    /// The ids Settings offers, in the order it offers them. Adding a language is this
    /// array plus a column in the catalog — there is no third place.
    static let offeredIDs = [systemID, "en", "zh-Hans"]

    /// Where the compiled catalog actually lives. `Scripts/bundle.sh` runs xcstringstool
    /// and drops `<lang>.lproj` into `Contents/Resources`, which is `Bundle.main`; a bare
    /// `swift build` product has only SwiftPM's resource bundle beside the binary, which
    /// holds the uncompiled `.xcstrings` and so answers every lookup with the key.
    ///
    /// The branch is not cosmetic. SwiftPM's generated `Bundle.module` accessor falls back
    /// to an absolute path inside *this* machine's build directory and calls `fatalError`
    /// when neither candidate exists — evaluating it from a shipped .app would be a launch
    /// crash, so the packaged branch must never touch it.
    static let catalog: Bundle = {
        let compiled = Bundle.main.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: "en"
        )
        return compiled != nil ? .main : .module
    }()

    /// Which bundle answers a lookup, and under whose plural rules.
    ///
    /// Following the system is `catalog` with no locale of our own: `String(localized:)`
    /// then resolves against the app's localizations the way it would in an app that had
    /// never heard of this file. Choosing a language is a bundle made from that language's
    /// `.lproj` directory, which contains exactly one localization — so the choice is
    /// expressed as *where to look*, not as an override applied afterwards.
    struct Route {
        let bundle: Bundle
        /// nil means `Locale.current`. It is set for a chosen language because plurals are
        /// selected by locale, not by bundle: a zh-Hans stringsdict with only an `other`
        /// case read under English rules is a coincidence that works until a language has
        /// a `one` case the English rules do not ask for.
        let locale: Locale?

        static let system = Route(bundle: catalog, locale: nil)

        /// Pure, and takes its own base bundle, so the three cases worth checking —
        /// follows the system, finds the language, cannot find it — are testable against a
        /// directory rather than against whatever this machine's app happens to contain.
        static func resolve(_ id: String, in base: Bundle) -> Route {
            guard id != systemID,
                  let path = base.path(forResource: id, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else {
                // An id nobody can satisfy — a language dropped from a later build, a typo
                // written into defaults by hand — falls back to the system rather than to
                // silence. A preference this app cannot honour is not a reason to answer
                // every lookup with the raw key.
                return Route(bundle: base, locale: nil)
            }
            return Route(bundle: bundle, locale: Locale(identifier: id))
        }
    }

    /// Written only from `Language.use(_:)`, which is main-actor; read from wherever a
    /// sentence is needed, and that includes the decode queue (`PluckService`) and the
    /// lazily-built status icon. `nonisolated(unsafe)` rather than a lock because the
    /// write replaces two immutable references wholesale: a lookup racing a language
    /// switch gets either the old sentence or the new one, and both are sentences.
    nonisolated(unsafe) static var route = Route.system

    static func s(_ key: String.LocalizationValue) -> String {
        // A SwiftUI body that asks for a sentence is, by that act, asking to be re-run when
        // the language changes — so touching the observable id here is what subscribes it,
        // and it is the reason no view has to remember to. Guarded by the thread because
        // the same function is called from off the main actor, where there is no observation
        // in progress to register with and nothing to subscribe.
        if Thread.isMainThread {
            MainActor.assumeIsolated { _ = Language.shared.id }
        }
        let route = route
        return String(localized: key, bundle: route.bundle, locale: route.locale ?? .current)
    }
}

extension Notification.Name {
    /// Posted after the routing has already changed, so a handler that rebuilds a menu or
    /// a window title reads the new language by simply asking for it.
    ///
    /// This is the AppKit half of the switch. SwiftUI needs nothing: its bodies call `L.s`,
    /// `L.s` touches `Language.shared.id`, and the observation does the rest. What cannot
    /// observe is everything built once and kept — `NSApp.mainMenu`, `NSWindow.title`, the
    /// status item's accessibility label — and those are what this notification is for.
    static let pluckLanguageDidChange = Notification.Name("pluck.languageDidChange")
}

/// The language the app is currently speaking.
///
/// Separate from `Preferences` because it is a different kind of thing: `Preferences` is
/// what is remembered across launches, and this is what is true right now. `Preferences`
/// pushes into it; nothing pushes the other way.
@MainActor
@Observable
final class Language {
    static let shared = Language()

    /// Observable, and read by every `L.s` call that happens on the main actor. Changing it
    /// is what makes a running window redraw itself in another language.
    private(set) var id: String = L.systemID

    /// Idempotent, so `Preferences` can call it on every launch without posting a change
    /// nobody made.
    func use(_ id: String) {
        guard id != self.id else { return }
        self.id = id
        L.route = L.Route.resolve(id, in: L.catalog)
        NotificationCenter.default.post(name: .pluckLanguageDidChange, object: self)
    }
}
