import Foundation
import XCTest

@testable import PluckApp

@MainActor
final class RecentStoreTests: XCTestCase {
    private func item(_ marker: UInt8, name: String = "shot") -> RecentItem {
        let data = Data([marker, marker, marker])
        let directory = URL(fileURLWithPath: "/tmp/Pluck/\(marker)", isDirectory: true)
        return RecentItem(
            fingerprint: PluckService.fingerprint(data),
            thumbnailPNG: data,
            fileURL: directory.appendingPathComponent("\(name).png"),
            originalURL: directory.appendingPathComponent("original.png"),
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

    /// The entry pushed off the end owns three files. Nothing else in the app knows it is
    /// gone, so if `insert` does not report it the cutout stays on disk forever — the exact
    /// leak the launch sweep exists to prevent, reintroduced one eviction at a time.
    func testEvictedEntriesAreReportedSoTheirFilesCanGo() {
        let store = RecentStore(capacity: 2)
        store.insert(item(1))
        store.insert(item(2))
        let result = store.insert(item(3))
        XCTAssertEqual(result.evicted.map(\.fingerprint), [item(1).fingerprint])
    }

    /// Twenty, matching what survives a relaunch: a grid that holds more than the history
    /// does would silently shrink the first time the app is reopened.
    func testDefaultCapacityMatchesThePersistedHistory() {
        XCTAssertEqual(RecentStore.defaultCapacity, 20)
        let store = RecentStore()
        for i in 1...25 { store.insert(item(UInt8(i))) }
        XCTAssertEqual(store.items.count, 20)
        XCTAssertEqual(store.items.first?.fingerprint, item(25).fingerprint)
        XCTAssertEqual(store.items.last?.fingerprint, item(6).fingerprint)
    }

    /// The preview slider's "before" half is a second file beside the cutout; losing the
    /// pointer to it on insert would silently degrade the panel to a cutout-only view.
    func testTheOriginalsLocationSurvivesTheStore() {
        let store = RecentStore()
        store.insert(item(7))
        XCTAssertEqual(store.items.first?.originalURL.lastPathComponent, "original.png")
    }

    func testDuplicateFingerprintPromotesInsteadOfDuplicating() {
        let store = RecentStore()
        store.insert(item(1))
        store.insert(item(2))
        store.insert(item(1, name: "again"))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.fingerprint, item(1).fingerprint)
        // Promotion keeps the original entry: its files are the ones already on disk.
        XCTAssertEqual(store.items.first?.suggestedName, "shot")
    }

    /// The return value is the whole point of the de-duplication fix: a silent promotion
    /// is what made "drag a cutout back in" look like a failure, so the caller has to be
    /// able to tell the two outcomes apart and flash the row it landed in.
    func testInsertReportsWhetherItDeduplicated() {
        let store = RecentStore()
        let first = item(1)
        XCTAssertNil(store.insert(first).promoted)
        XCTAssertNil(store.insert(item(2)).promoted)
        XCTAssertEqual(store.insert(item(1, name: "again")).promoted, first.id)
    }

    /// The promoted id must be the *surviving* entry's, not the rejected duplicate's —
    /// highlighting an id that is not in the grid would flash nothing at all.
    func testPromotedCarriesTheSurvivingItemsID() {
        let store = RecentStore()
        let original = item(1)
        store.insert(original)
        let duplicate = item(1, name: "again")
        XCTAssertNotEqual(original.id, duplicate.id)
        XCTAssertEqual(store.insert(duplicate).promoted, original.id)
        XCTAssertEqual(store.items.first?.id, original.id)
    }

    func testClearReturnsTheEntriesSoTheCallerCanDeleteTheirFiles() {
        let store = RecentStore()
        store.insert(item(1))
        store.insert(item(2))
        let cleared = store.clear()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(Set(cleared.map(\.fileURL)), Set([item(1), item(2)].map(\.fileURL)))
    }

    /// Restoring is not inserting: the entries arrive already ordered and already
    /// de-duplicated, and running them back through `insert` would rewrite the index they
    /// were just read from, once per entry, before the first frame is drawn.
    func testRestoreSeedsWithoutNotifyingTheArchive() {
        let store = RecentStore()
        var writes = 0
        store.onChange = { _ in writes += 1 }
        store.restore([item(2), item(1)])
        XCTAssertEqual(store.items.map(\.fingerprint), [item(2).fingerprint, item(1).fingerprint])
        XCTAssertEqual(writes, 0)
    }

    func testRestoreHonoursTheCap() {
        let store = RecentStore(capacity: 2)
        store.restore([item(1), item(2), item(3)])
        XCTAssertEqual(store.items.count, 2)
    }

    /// Persistence hangs off this one hook, so every mutation has to reach it.
    func testEveryMutationNotifiesTheArchive() {
        let store = RecentStore()
        var seen: [Int] = []
        store.onChange = { seen.append($0.count) }
        store.insert(item(1))
        store.insert(item(2))
        store.insert(item(1, name: "again"))
        store.clear()
        XCTAssertEqual(seen, [1, 2, 2, 0])
    }

    func testFingerprintIsContentAddressed() {
        XCTAssertEqual(PluckService.fingerprint(Data([1, 2])), PluckService.fingerprint(Data([1, 2])))
        XCTAssertNotEqual(PluckService.fingerprint(Data([1, 2])), PluckService.fingerprint(Data([1, 3])))
    }
}
