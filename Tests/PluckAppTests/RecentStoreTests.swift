import Foundation
import XCTest

@testable import PluckApp

@MainActor
final class RecentStoreTests: XCTestCase {
    private func item(_ marker: UInt8, name: String = "shot") -> RecentItem {
        let data = Data([marker, marker, marker])
        return RecentItem(
            fingerprint: PluckService.fingerprint(data),
            pngData: data,
            thumbnailPNG: data,
            originalPNG: Data([marker, 0xFF]),
            fileURL: URL(fileURLWithPath: "/tmp/\(marker).png"),
            suggestedName: name
        )
    }

    func testNewestFirst() {
        let store = RecentStore()
        store.insert(item(1))
        store.insert(item(2))
        XCTAssertEqual(store.items.map(\.fingerprint), [item(2).fingerprint, item(1).fingerprint])
    }

    func testCapacityDropsOldest() {
        let store = RecentStore(capacity: 3)
        for i in 1...5 { store.insert(item(UInt8(i))) }
        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items.map(\.fingerprint), [5, 4, 3].map { item(UInt8($0)).fingerprint })
    }

    /// Twelve, not nine: the compact drop strip freed a fourth grid row.
    func testDefaultCapacityIsTwelve() {
        XCTAssertEqual(RecentStore.defaultCapacity, 12)
        let store = RecentStore()
        for i in 1...20 { store.insert(item(UInt8(i))) }
        XCTAssertEqual(store.items.count, 12)
        XCTAssertEqual(store.items.first?.fingerprint, item(20).fingerprint)
        XCTAssertEqual(store.items.last?.fingerprint, item(9).fingerprint)
    }

    /// The preview slider's "before" half lives on the item; losing it on insert would
    /// silently degrade the panel to a cutout-only view.
    func testOriginalIsCarriedThroughTheStore() {
        let store = RecentStore()
        store.insert(item(7))
        XCTAssertEqual(store.items.first?.originalPNG, Data([7, 0xFF]))
    }

    func testDuplicateFingerprintPromotesInsteadOfDuplicating() {
        let store = RecentStore()
        store.insert(item(1))
        store.insert(item(2))
        store.insert(item(1, name: "again"))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.fingerprint, item(1).fingerprint)
        // Promotion keeps the original entry: its temp file is the one already on disk.
        XCTAssertEqual(store.items.first?.suggestedName, "shot")
    }

    /// The return value is the whole point of the de-duplication fix: a silent promotion
    /// is what made "drag a cutout back in" look like a failure, so the caller has to be
    /// able to tell the two outcomes apart and flash the row it landed in.
    func testInsertReportsWhetherItDeduplicated() {
        let store = RecentStore()
        let first = item(1)
        XCTAssertEqual(store.insert(first), .inserted)
        XCTAssertEqual(store.insert(item(2)), .inserted)
        XCTAssertEqual(store.insert(item(1, name: "again")), .promoted(first.id))
    }

    /// The promoted id must be the *surviving* entry's, not the rejected duplicate's —
    /// highlighting an id that is not in the grid would flash nothing at all.
    func testPromotedCarriesTheSurvivingItemsID() {
        let store = RecentStore()
        let original = item(1)
        store.insert(original)
        let duplicate = item(1, name: "again")
        XCTAssertNotEqual(original.id, duplicate.id)
        XCTAssertEqual(store.insert(duplicate), .promoted(original.id))
        XCTAssertEqual(store.items.first?.id, original.id)
    }

    func testClearReturnsBackingFilesSoTheCallerCanDeleteThem() {
        let store = RecentStore()
        store.insert(item(1))
        store.insert(item(2))
        let urls = store.clear()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(Set(urls), [URL(fileURLWithPath: "/tmp/2.png"), URL(fileURLWithPath: "/tmp/1.png")])
    }

    func testFingerprintIsContentAddressed() {
        XCTAssertEqual(PluckService.fingerprint(Data([1, 2])), PluckService.fingerprint(Data([1, 2])))
        XCTAssertNotEqual(PluckService.fingerprint(Data([1, 2])), PluckService.fingerprint(Data([1, 3])))
    }
}
