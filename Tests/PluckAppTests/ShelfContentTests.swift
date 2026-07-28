import Foundation
import XCTest

@testable import PluckApp

/// The shelf no longer has a standing drop banner: the invitation lives in the grid as a
/// dashed ghost slot, which means "is there a ghost, and is it a cell or the whole panel"
/// is now a real decision rather than a cosmetic one. It is a pure function precisely so
/// the transitions — first drop, last delete, a placeholder with nothing behind it — can be
/// checked without a screen.
final class ShelfContentTests: XCTestCase {
    func testNothingPluckedYetShowsTheFullSizeInvitation() {
        let content = ShelfContent.resolve(pending: 0, recents: 0)
        XCTAssertEqual(content, .invitation)
        // The invitation *is* the ghost, grown; drawing a cell-sized one inside it would be
        // the same affordance twice.
        XCTAssertFalse(content.showsGhostCell)
        // Nothing to label, and nothing to clear.
        XCTAssertFalse(content.showsSectionLabel)
        XCTAssertFalse(ShelfContent.showsClear(recents: 0))
    }

    func testTheFirstDropCollapsesTheInvitationIntoACell() {
        // The placeholder arrives before any result exists, and it is the moment the panel
        // switches languages — from "drop here" to "here is what you dropped".
        let content = ShelfContent.resolve(pending: 1, recents: 0)
        XCTAssertEqual(content, .grid)
        XCTAssertTrue(content.showsGhostCell)
        XCTAssertTrue(content.showsSectionLabel)
    }

    func testResultsKeepTheGhostAsTheFirstCell() {
        let content = ShelfContent.resolve(pending: 0, recents: 4)
        XCTAssertEqual(content, .grid)
        XCTAssertTrue(content.showsGhostCell)
    }

    /// Clear tracks the store rather than the content. A shelf holding only in-flight
    /// placeholders is a grid, but pressing Clear on it would remove nothing while looking
    /// like it should remove everything on screen.
    func testClearOnlyAppearsWhenThereIsSomethingToClear() {
        XCTAssertFalse(ShelfContent.showsClear(recents: 0))
        XCTAssertTrue(ShelfContent.showsClear(recents: 1))
    }

    /// Deleting the last cutout has to land back on the invitation, not on an empty grid
    /// with a lone ghost cell floating in the top left.
    func testDeletingTheLastCutoutReturnsToTheInvitation() {
        XCTAssertEqual(ShelfContent.resolve(pending: 0, recents: 1), .grid)
        XCTAssertEqual(ShelfContent.resolve(pending: 0, recents: 0), .invitation)
    }
}

/// Delete, the one destructive item in the new context menu. Everything else in that menu
/// is a second doorway to a path the hover buttons already had; this is the only one that
/// takes something away, and the only caller that removes a single entry rather than all.
@MainActor
final class ShelfDeleteTests: XCTestCase {
    private func item(_ marker: UInt8) -> RecentItem {
        let data = Data([marker])
        let directory = URL(fileURLWithPath: "/tmp/PluckDeleteTests/\(marker)", isDirectory: true)
        return RecentItem(
            fingerprint: PluckService.fingerprint(data),
            thumbnailPNG: data,
            fileURL: directory.appendingPathComponent("cutout.png"),
            originalURL: directory.appendingPathComponent("original.png"),
            suggestedName: "cutout"
        )
    }

    func testDeletingOneCutoutLeavesTheRestOfTheGridAlone() {
        let model = AppModel()
        let first = item(1)
        let second = item(2)
        model.recents.insert(first)
        model.recents.insert(second)
        model.discard(first)
        XCTAssertEqual(model.recents.items.map { $0.id }, [second.id])
    }

    func testDeletingSomethingAlreadyGoneIsHarmless() {
        let model = AppModel()
        model.recents.insert(item(1))
        model.discard(item(2))
        XCTAssertEqual(model.recents.items.count, 1)
    }
}
