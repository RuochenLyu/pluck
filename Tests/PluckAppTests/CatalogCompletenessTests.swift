import Foundation
import XCTest

@testable import PluckApp

/// The one thing a String Catalog cannot tell you by failing: a key nobody translated
/// renders as its English self, which is correct copy in the wrong language and therefore
/// invisible in a screenshot of a mostly-Chinese window. This is the assertion that a
/// string added next month gets noticed.
final class CatalogCompletenessTests: XCTestCase {
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/PluckApp/Resources/Localizable.xcstrings")

    private struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]

        struct Entry: Decodable {
            let localizations: [String: Localization]?
        }

        /// Either a plain unit or a set of plural variations. Both count as translated;
        /// what is being asserted is that the language was thought about, not which shape
        /// the thought took.
        struct Localization: Decodable {
            let stringUnit: Unit?
            let variations: Variations?

            struct Unit: Decodable { let value: String }
            struct Variations: Decodable { let plural: [String: Localization]? }

            var isTranslated: Bool {
                if let stringUnit { return !stringUnit.value.isEmpty }
                guard let plural = variations?.plural, !plural.isEmpty else { return false }
                return plural.values.allSatisfy(\.isTranslated)
            }
        }
    }

    private func loadCatalog() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.catalogURL))
    }

    func testEveryKeyIsWrittenInSimplifiedChinese() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(catalog.sourceLanguage, "en")
        let untranslated = catalog.strings
            .filter { $0.value.localizations?["zh-Hans"]?.isTranslated != true }
            .keys
            .sorted()
        XCTAssertEqual(
            untranslated, [],
            "these keys have no zh-Hans copy — they will render in English inside a Chinese window"
        )
    }

    /// The source language too, because the keys *are* the English copy and an entry that
    /// lost its `en` unit is a key that would have to be retyped to be corrected.
    func testEveryKeyKeepsItsEnglish() throws {
        let untranslated = try loadCatalog().strings
            .filter { $0.value.localizations?["en"]?.isTranslated != true }
            .keys
            .sorted()
        XCTAssertEqual(untranslated, [])
    }

    /// Every id Settings offers has to be a language the catalog can actually answer in —
    /// `system` excepted, which is the absence of a choice.
    func testSettingsOffersOnlyLanguagesTheCatalogCarries() throws {
        let catalog = try loadCatalog()
        let carried = Set(catalog.strings.values.flatMap { $0.localizations?.keys ?? [:].keys })
        for id in L.offeredIDs where id != L.systemID {
            XCTAssertTrue(carried.contains(id), "Settings offers \(id), which the catalog does not carry")
        }
    }
}
