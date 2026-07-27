import Foundation

/// Every user-visible string goes through here so the String Catalog stays the single
/// source of copy. Bare literals in views are a build-review failure, not a style nit.
///
/// Keys are the English copy itself, which matters right now: SwiftPM copies
/// `Localizable.xcstrings` into the resource bundle without running `xcstringstool`, so
/// lookups miss and fall back to the key — correct English either way. The v0.2 Xcode
/// app shell compiles the catalog properly and the first non-English locale starts working
/// with no code change.
enum L {
    static func s(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
