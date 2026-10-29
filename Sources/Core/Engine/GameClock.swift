import Foundation

/// Abstraction over "now" so the offline simulator can be tested without
/// waiting, without mocking `Date()`, and without any test-only branches inside
/// production code.
protocol GameClock: Sendable {
    var now: Date { get }
}

struct SystemClock: GameClock {
    var now: Date { Date() }
}

/// A clock the test suite (or a debug screen) can drive by hand.
struct FixedClock: GameClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    init(offsetFrom reference: Date, by interval: TimeInterval) {
        self.now = reference.addingTimeInterval(interval)
    }
}
