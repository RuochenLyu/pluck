import Foundation

/// Matting is CPU- and ANE-bound synchronous work wearing an `async` coat. Run straight
/// from a `Task`, it occupies a thread of Swift's cooperative pool — a pool sized to the
/// core count and shared by everything else in the process — for its entire duration.
///
/// One image at a time, that is merely impolite. A folder of forty is a different thing:
/// the pool fills with blocking calls, and every full-resolution input, mask and composite
/// in flight is resident at the same time. A 12 MP photo is ~48 MB per buffer and a run
/// holds three, so "however many files the user dropped" is not a number that may decide
/// how much memory this app uses.
///
/// So: a private thread pool, and a fixed number of runs allowed into it at once.
public actor PluckQueue {
    /// Every `PluckPipeline.run` in the process goes through this one, which is the point:
    /// the app's drops, the CLI's globs and the Finder extension's selection are all the
    /// same machine's cores.
    public static let shared = PluckQueue()

    /// Vision serialises on the neural engine regardless, so width buys far less throughput
    /// than it costs in resident memory. Two is the floor because one would make a slow
    /// image block a fast one behind it for no reason.
    public static let defaultWidth = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 3))

    private let width: Int
    private let threads: DispatchQueue
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(width: Int = PluckQueue.defaultWidth, label: String = "com.aix4u.pluck.matting") {
        self.width = max(1, width)
        threads = DispatchQueue(label: label, qos: .userInitiated, attributes: .concurrent)
    }

    /// Suspends until a slot is free, then runs `body` on a thread this queue owns.
    ///
    /// Admission is what keeps the memory bounded; the hop off the cooperative pool is what
    /// keeps the rest of the process responsive while `body` blocks. Both are needed —
    /// gating alone would still park `width` cooperative threads on synchronous work.
    public func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        // Checked after admission rather than before: a job cancelled while queued still
        // has to take its turn, but it gives the slot straight back instead of decoding a
        // picture nobody is waiting for any more.
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            threads.async { continuation.resume(with: Result(catching: body)) }
        }
    }

    private func acquire() async {
        guard running >= width else {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// The slot is handed to the next waiter rather than freed and re-taken: dropping
    /// `running` here would let a caller that arrives between the two steps overtake a
    /// queue of jobs that have been waiting longer.
    private func release() {
        guard !waiting.isEmpty else {
            running -= 1
            return
        }
        waiting.removeFirst().resume()
    }

    /// Test seam. Nothing in the app has any business steering on this.
    var inFlight: Int { running }
}
