import Foundation

/// The second line of a batch row: how big the cutout is, and how long ago it was made.
///
/// Pure, and a type of its own, for two reasons. The pixel count must never be
/// group-formatted — a 1024px image that calls itself "1,024" is a number pretending to be
/// prose — and "how long ago" is the kind of thing that is obviously right until the clock
/// is one second past the boundary, so it takes a `now` and a test rather than a screenshot.
enum RowSubtitle {
    /// `engine` is the human name of the engine, or nil when there is nothing to say — which
    /// is every cutout made by the default (`EngineLabels.mark`). Marking those would print
    /// the same word on every row in a list where it is almost always the same word.
    static func text(
        width: Int,
        height: Int,
        createdAt: Date,
        engine: String? = nil,
        now: Date = Date()
    ) -> String {
        let parts = [
            dimensions(width: width, height: height),
            relative(createdAt, to: now)
        ] + [engine].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    static func dimensions(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }

    /// Under a minute is "Just now": the system formatter says "0 seconds ago" there, which
    /// is both wrong-sounding and stale the instant it is drawn.
    static func relative(_ date: Date, to now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return L.s("Just now") }
        // Built per call rather than cached: `RelativeDateTimeFormatter` is not `Sendable`,
        // and a handful of allocations per redraw of a twenty-row list is not the cost
        // worth taking a global for.
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
