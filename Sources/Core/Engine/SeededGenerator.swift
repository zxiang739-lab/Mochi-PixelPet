import Foundation

/// Deterministic RNG (SplitMix64).
///
/// The product spec requires the event engine to be *reproducible*. Using
/// `SystemRandomNumberGenerator` would make that impossible to verify, so every
/// engine takes an injected generator and tests replay with a fixed seed.
/// Seeding happens per-settlement from `(petID, lastSimulatedAt)` in the app so
/// that a given save always produces the same history even across relaunches.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        // 0 is a fixed point for SplitMix64; anything else works.
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    init(petID: UUID, timestamp: Date) {
        let uuid = petID.uuid
        var hash = UInt64(uuid.2) << 48 | UInt64(uuid.3) << 32
                 | UInt64(uuid.4) << 16 | UInt64(uuid.5)
        hash ^= UInt64(bitPattern: Int64(timestamp.timeIntervalSince1970 * 1000))
        self.init(seed: hash)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in 0..<1.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
