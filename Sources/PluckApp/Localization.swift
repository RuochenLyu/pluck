import Foundation

/// Every user-visible string goes through here so the String Catalog stays the single
/// source of copy. Bare literals in views are a build-review failure, not a style nit.
///
/// Keys are the English copy itself, so a missed lookup still renders correct English —
/// which is exactly why the packaging step has to be verified rather than trusted.
enum L {
    /// Where the compiled catalog actually lives. `Scripts/bundle.sh` runs xcstringstool
    /// and drops `<lang>.lproj` into `Contents/Resources`, which is `Bundle.main`; a bare
    /// `swift build` product has only SwiftPM's resource bundle beside the binary, which
    /// holds the uncompiled `.xcstrings` and so answers every lookup with the key.
    ///
    /// The branch is not cosmetic. SwiftPM's generated `Bundle.module` accessor falls back
    /// to an absolute path inside *this* machine's build directory and calls `fatalError`
    /// when neither candidate exists — evaluating it from a shipped .app would be a launch
    /// crash, so the packaged branch must never touch it.
    private static let catalog: Bundle = {
        let compiled = Bundle.main.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: "en"
        )
        return compiled != nil ? .main : .module
    }()

    static func s(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: catalog)
    }
}
