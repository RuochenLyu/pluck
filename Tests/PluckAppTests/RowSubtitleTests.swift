import Foundation
import XCTest

@testable import PluckApp

/// The batch row's second line. Both halves have a way of being wrong that looks fine in a
/// screenshot taken one second after a drop: a pixel count rendered as prose ("1,024"), and
/// a "0 seconds ago" that was stale before it finished drawing.
final class RowSubtitleTests: XCTestCase {
    private let made = Date(timeIntervalSinceReferenceDate: 700_000_000)

    /// The regression this line inherited from the row it replaced: `Text` treats a literal
    /// as a localization key and group-formats the numbers inside it.
    func testPixelCountsAreNotGroupFormatted() {
        let text = RowSubtitle.dimensions(width: 1024, height: 2048)
        XCTAssertEqual(text, "1024 × 2048")
    }

    func testFreshCutoutsSayJustNow() {
        XCTAssertEqual(RowSubtitle.relative(made, to: made), L.s("Just now"))
        XCTAssertEqual(RowSubtitle.relative(made, to: made.addingTimeInterval(59)), L.s("Just now"))
    }

    /// One minute is where the system formatter starts having something true to say.
    func testOlderCutoutsGetARelativeTime() {
        let older = RowSubtitle.relative(made, to: made.addingTimeInterval(3 * 3600))
        XCTAssertNotEqual(older, L.s("Just now"))
        XCTAssertFalse(older.isEmpty)
    }

    func testTheSubtitleIsSizeThenTime() {
        let text = RowSubtitle.text(width: 640, height: 480, createdAt: made, now: made)
        XCTAssertEqual(text, "640 × 480 · \(L.s("Just now"))")
    }

    /// Provenance is appended only when there is a departure from the default to report;
    /// `EngineLabels.mark` decides that, and nil has to leave the line exactly as it was.
    func testANamedEngineIsAppendedAndNothingIsAppendedWithoutOne() {
        XCTAssertEqual(
            RowSubtitle.text(width: 640, height: 480, createdAt: made, engine: L.s("Fine Edges"), now: made),
            "640 × 480 · \(L.s("Just now")) · \(L.s("Fine Edges"))"
        )
        XCTAssertEqual(
            RowSubtitle.text(width: 640, height: 480, createdAt: made, engine: nil, now: made),
            "640 × 480 · \(L.s("Just now"))"
        )
    }
}
