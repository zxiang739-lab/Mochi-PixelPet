import Foundation

/// A numeric pet attribute that can never leave its declared range.
///
/// Every mutation in the codebase funnels through `set(_:)` or `adjust(by:)`,
/// so an out-of-range value is structurally impossible rather than merely
/// unlikely. This is what makes the offline simulator safe to build on: a
/// corrupt clock, a first-launch timestamp bug, or a hostile date change can
/// produce any delta it likes and the value still lands inside the legal range.
struct BoundedStat: Codable, Hashable, Sendable {
    static let unitRange: ClosedRange<Double> = 0...100

    let range: ClosedRange<Double>
    private(set) var value: Double

    init(_ value: Double, in range: ClosedRange<Double> = BoundedStat.unitRange) {
        precondition(range.lowerBound < range.upperBound, "BoundedStat requires a non-empty range")
        self.range = range
        self.value = BoundedStat.clamp(value, to: range)
    }

    /// 0...1 position of the value inside its range.
    var normalized: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var isEmpty: Bool { value <= range.lowerBound + 0.0001 }
    var isFull: Bool { value >= range.upperBound - 0.0001 }

    mutating func set(_ newValue: Double) {
        value = BoundedStat.clamp(newValue, to: range)
    }

    /// Applies `delta` and returns the delta that actually landed after clamping.
    /// Non-finite input is ignored so a NaN can never poison persisted state.
    @discardableResult
    mutating func adjust(by delta: Double) -> Double {
        guard delta.isFinite, delta != 0 else { return 0 }
        let before = value
        set(value + delta)
        return value - before
    }

    /// Moves a fraction of the way toward `target`. Used for gradual drift such
    /// as mood easing back toward neutral while the pet is left alone.
    mutating func ease(toward target: Double, rate: Double, over seconds: TimeInterval) {
        guard rate > 0, seconds > 0 else { return }
        // Exponential ease keeps long offline windows well-behaved: the value
        // approaches the target instead of overshooting past it.
        let factor = 1 - exp(-rate * seconds)
        set(value + (target - value) * factor)
    }

    private static func clamp(_ raw: Double, to range: ClosedRange<Double>) -> Double {
        guard !raw.isNaN else { return range.lowerBound }
        return min(max(raw, range.lowerBound), range.upperBound)
    }
}
