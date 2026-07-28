import Foundation
import XCTest

@testable import PluckApp

/// Selection is the one part of the gallery that is a rule rather than a drawing, and the
/// export button reads its file set straight off it. Every case here is one the pointer can
/// produce in two clicks.
final class GallerySelectionTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    func testAClickSelectsExactlyOneCard() {
        var selection = GallerySelection()
        selection.click(a)
        XCTAssertTrue(selection.contains(a))
        XCTAssertEqual(selection.count, 1)
    }

    /// The gesture that selects also undoes itself — there is no other affordance on a card
    /// for "never mind", and Esc is a keyboard away.
    func testClickingTheOneSelectedCardAgainClearsIt() {
        var selection = GallerySelection()
        selection.click(a)
        selection.click(a)
        XCTAssertTrue(selection.isEmpty)
    }

    /// Without ⌘ a click means "that one", not "that one as well". A plain click landing on a
    /// second card while three are selected has to replace the lot, or the user who meant to
    /// start over ends up exporting four.
    func testAPlainClickReplacesAMultipleSelection() {
        var selection = GallerySelection()
        selection.selectAll([a, b, c])
        selection.click(b)
        XCTAssertEqual(selection.ids, [b])
    }

    func testCommandClickAddsAndRemoves() {
        var selection = GallerySelection()
        selection.click(a)
        selection.click(b, extending: true)
        XCTAssertEqual(selection.ids, [a, b])
        selection.click(a, extending: true)
        XCTAssertEqual(selection.ids, [b])
    }

    /// ⌘-clicking the last selected card leaves nothing selected, which is a legal state:
    /// the export button goes back to saying "Export All…".
    func testCommandClickCanEmptyTheSelection() {
        var selection = GallerySelection()
        selection.click(a)
        selection.click(a, extending: true)
        XCTAssertTrue(selection.isEmpty)
    }

    func testSelectAllTakesTheWholeGridAndEscapeGivesItBack() {
        var selection = GallerySelection()
        selection.selectAll([a, b, c])
        XCTAssertEqual(selection.count, 3)
        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    /// The case that makes this a type rather than a `Set` in a view: deleting a selected
    /// cutout must not leave the button counting a file that is no longer there — Export
    /// would then write two while saying three.
    func testDeletingASelectedCutoutDropsItFromTheSelection() {
        var selection = GallerySelection()
        selection.selectAll([a, b, c])
        selection.prune(to: [a, c])
        XCTAssertEqual(selection.ids, [a, c])
    }
}

/// What Export would actually write, which is the second half of the same rule: the label
/// says a number, and the number has to be the length of this array.
@MainActor
final class GalleryExportTargetTests: XCTestCase {
    private func item(_ marker: UInt8) -> RecentItem {
        let data = Data([marker])
        let directory = URL(fileURLWithPath: "/tmp/PluckGalleryTests/\(marker)", isDirectory: true)
        return RecentItem(
            fingerprint: PluckService.fingerprint(data),
            thumbnailPNG: data,
            fileURL: directory.appendingPathComponent("cutout.png"),
            originalURL: directory.appendingPathComponent("original.png"),
            suggestedName: "cutout-\(marker)"
        )
    }

    /// No selection means the whole grid: the button says "Export All…" and it means it.
    func testWithNothingSelectedTheTargetIsEverything() {
        let model = AppModel()
        let first = item(1)
        let second = item(2)
        model.recents.insert(first)
        model.recents.insert(second)
        XCTAssertEqual(model.exportTargets.count, 2)
    }

    func testWithASelectionTheTargetIsExactlyTheSelectedCutouts() {
        let model = AppModel()
        let first = item(1)
        let second = item(2)
        let third = item(3)
        [first, second, third].forEach { model.recents.insert($0) }
        model.select(first)
        model.select(third, extending: true)
        XCTAssertEqual(Set(model.exportTargets.map(\.id)), [first.id, third.id])
    }

    /// In the grid's order, not the set's. Export numbers colliding filenames as it goes, so
    /// an iteration order that changed run to run would rename different files each time.
    func testTheTargetKeepsTheOrderTheGridIsShowing() {
        let model = AppModel()
        let items = [item(1), item(2), item(3)]
        items.forEach { model.recents.insert($0) }
        model.selectAll()
        XCTAssertEqual(model.exportTargets.map(\.id), model.recents.items.map(\.id))
    }

    func testSelectAllTakesEveryCutoutAndEscapeReturnsToExportAll() {
        let model = AppModel()
        [item(1), item(2)].forEach { model.recents.insert($0) }
        model.selectAll()
        XCTAssertEqual(model.selection.count, 2)
        model.clearSelection()
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.exportTargets.count, 2, "an empty selection exports the grid")
    }

    /// Deleting one of the selected cards through the context menu, which is the path a user
    /// actually takes to it.
    func testDeletingASelectedCutoutShrinksTheExportSet() {
        let model = AppModel()
        let first = item(1)
        let second = item(2)
        model.recents.insert(first)
        model.recents.insert(second)
        model.selectAll()
        model.discard(second)
        XCTAssertEqual(model.selection.count, 1)
        XCTAssertEqual(model.exportTargets.map(\.id), [first.id])
    }

    func testClearingTheGridClearsTheSelectionWithIt() {
        let model = AppModel()
        [item(1), item(2)].forEach { model.recents.insert($0) }
        model.selectAll()
        model.clearRecents()
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.exportTargets.isEmpty)
    }
}

/// The caption that floats up over a card on hover.
final class GalleryCaptionTests: XCTestCase {
    /// The reason this is a function and not string interpolation in the view: SwiftUI
    /// group-formats an interpolated `Int` in a `LocalizedStringKey`, and a 1024px image that
    /// calls itself "1,024" is a number pretending to be prose.
    func testPixelCountsAreNeverGroupFormatted() {
        XCTAssertEqual(GalleryCaption.dimensions(width: 1024, height: 2048), "1024 × 2048")
    }

    func testACaptionIsTheNameAndTheSize() {
        XCTAssertEqual(
            GalleryCaption.text(name: "IMG_0042", width: 640, height: 480),
            "IMG_0042 · 640 × 480"
        )
    }

    /// Only a departure from the default engine is worth naming; a nil engine has to take its
    /// separator with it, or every Vision cutout ends in a dangling "·".
    func testTheEngineIsNamedOnlyWhenThereIsOneToName() {
        XCTAssertEqual(
            GalleryCaption.text(name: "cup", width: 640, height: 480, engine: L.s("Fine Edges")),
            "cup · 640 × 480 · \(L.s("Fine Edges"))"
        )
        XCTAssertEqual(
            GalleryCaption.text(name: "cup", width: 640, height: 480, engine: nil),
            "cup · 640 × 480"
        )
    }
}
