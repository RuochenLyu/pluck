import Foundation
import XCTest

@testable import PluckKit

/// Counts how many bodies are inside the queue at once. A plain `Int` would need a lock of
/// its own; an actor is the lock, and `await`-ing it from inside the body is exactly the
/// interleaving point the test wants to observe.
private actor Occupancy {
    private(set) var peak = 0
    private var current = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}

final class PluckQueueTests: XCTestCase {
    /// The reason this type exists. Forty dropped files must not become forty
    /// full-resolution images resident at once, and nothing else in the pipeline is in a
    /// position to say no.
    func testNoMoreThanWidthBodiesRunAtOnce() async throws {
        let queue = PluckQueue(width: 3)
        let occupancy = Occupancy()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try? await queue.run {
                        // The body is synchronous by contract, so the observation has to be
                        // too: a semaphore round-trip through the actor, then real work to
                        // widen the window a genuine over-admission would show up in.
                        let done = DispatchSemaphore(value: 0)
                        Task { await occupancy.enter(); done.signal() }
                        done.wait()
                        Thread.sleep(forTimeInterval: 0.01)
                        let leaving = DispatchSemaphore(value: 0)
                        Task { await occupancy.leave(); leaving.signal() }
                        leaving.wait()
                    }
                }
            }
        }

        let peak = await occupancy.peak
        XCTAssertGreaterThan(peak, 1, "width 3 should actually overlap work")
        XCTAssertLessThanOrEqual(peak, 3)
    }

    func testEveryQueuedJobEventuallyRuns() async throws {
        let queue = PluckQueue(width: 2)
        let results = await withTaskGroup(of: Int.self) { group -> [Int] in
            for i in 0..<30 {
                group.addTask { (try? await queue.run { i }) ?? -1 }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(Set(results), Set(0..<30))
    }

    /// A slot lost on the error path is not a bug that shows up as an error — it shows up
    /// as the app quietly refusing to process anything, some indeterminate time later.
    func testAThrowingBodyGivesItsSlotBack() async throws {
        let queue = PluckQueue(width: 1)
        struct Boom: Error {}

        for _ in 0..<5 {
            do {
                try await queue.run { throw Boom() }
                XCTFail("expected the body's error to propagate")
            } catch is Boom {
            }
        }

        let value = try await queue.run { 42 }
        XCTAssertEqual(value, 42)
        let inFlight = await queue.inFlight
        XCTAssertEqual(inFlight, 0)
    }

    func testTheBodysErrorArrivesUnwrapped() async {
        let queue = PluckQueue(width: 1)
        do {
            try await queue.run { throw PluckError.noSubjectDetected }
            XCTFail("expected noSubjectDetected")
        } catch let error as PluckError {
            guard case .noSubjectDetected = error else {
                return XCTFail("expected noSubjectDetected, got \(error)")
            }
        } catch {
            XCTFail("expected PluckError, got \(error)")
        }
    }

    /// Cancelling a queued job has to reach it *before* it decodes anything — the whole
    /// point of a batch queue is that the tail of it is still cheap to call off.
    func testACancelledJobNeverRunsItsBody() async throws {
        let queue = PluckQueue(width: 1)
        let ran = Ran()

        let blocker = Task { try await queue.run { Thread.sleep(forTimeInterval: 0.2) } }
        let victim = Task { try await queue.run { ran.mark() } }
        // Long enough for `victim` to be parked in `waiting` rather than not yet started.
        try await Task.sleep(nanoseconds: 50_000_000)
        victim.cancel()

        try await blocker.value
        do {
            try await victim.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
        }
        XCTAssertFalse(ran.value)
    }

    /// Two on a single-core machine, four on anything with twelve cores or more. Neither
    /// end is arbitrary: one would serialise a batch needlessly, and above four the neural
    /// engine is the bottleneck and the extra buffers are pure cost.
    func testDefaultWidthStaysInItsLane() {
        XCTAssertGreaterThanOrEqual(PluckQueue.defaultWidth, 2)
        XCTAssertLessThanOrEqual(PluckQueue.defaultWidth, 4)
    }
}

/// A `Bool` the synchronous body can set and the test can read afterwards. Not concurrent:
/// the assertion happens after both tasks have finished.
private final class Ran: @unchecked Sendable {
    private(set) var value = false
    func mark() { value = true }
}
