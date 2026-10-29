import Foundation

/// The five behavioural dials that make one Mochi feel different from another.
///
/// Each value lives in 0...1 and only ever moves by tiny steps driven by
/// long-run behaviour statistics — never by a single interaction. That is a
/// deliberate design constraint from the product spec: personality must be
/// *earned*, slow, bounded and explainable.
enum PersonalityTrait: String, CaseIterable, Codable, Sendable {
    case liveliness
    case curiosity
    case affection
    case independence
    case laziness

    var displayName: String {
        switch self {
        case .liveliness:   "活泼"
        case .curiosity:    "好奇"
        case .affection:    "亲近"
        case .independence: "独立"
        case .laziness:     "慵懒"
        }
    }

    var symbolName: String {
        switch self {
        case .liveliness:   "bolt.heart"
        case .curiosity:    "sparkle.magnifyingglass"
        case .affection:    "heart.circle"
        case .independence: "figure.walk.motion"
        case .laziness:     "moon.zzz"
        }
    }
}

struct Personality: Codable, Hashable, Sendable {
    /// Hard ceiling on how far a single settlement pass may move a trait.
    static let maxStepPerSettlement = 0.006
    /// Hard ceiling on cumulative daily movement, so a long session of one
    /// activity cannot max out a trait in an afternoon.
    static let maxDailyDrift = 0.05

    private(set) var liveliness: Double
    private(set) var curiosity: Double
    private(set) var affection: Double
    private(set) var independence: Double
    private(set) var laziness: Double

    init(
        liveliness: Double = 0.5,
        curiosity: Double = 0.5,
        affection: Double = 0.5,
        independence: Double = 0.5,
        laziness: Double = 0.5
    ) {
        self.liveliness = Personality.clamp(liveliness)
        self.curiosity = Personality.clamp(curiosity)
        self.affection = Personality.clamp(affection)
        self.independence = Personality.clamp(independence)
        self.laziness = Personality.clamp(laziness)
    }

    static let neutral = Personality()

    subscript(trait: PersonalityTrait) -> Double {
        get {
            switch trait {
            case .liveliness:   liveliness
            case .curiosity:    curiosity
            case .affection:    affection
            case .independence: independence
            case .laziness:     laziness
            }
        }
        set { move(trait, to: newValue) }
    }

    /// The strongest trait, or `nil` when the creature is still evenly balanced.
    var dominant: PersonalityTrait? {
        let pairs = PersonalityTrait.allCases.map { ($0, self[$0]) }
        guard let best = pairs.max(by: { $0.1 < $1.1 }) else { return nil }
        // A trait only "dominates" once it has drifted meaningfully away from
        // the neutral 0.5 baseline and leads the runner-up by a real margin.
        let runnerUp = pairs.filter { $0.0 != best.0 }.map(\.1).max() ?? 0.5
        guard best.1 >= 0.56, best.1 - runnerUp >= 0.04 else { return nil }
        return best.0
    }

    /// 0.7...1.3 multiplier used to bias event weights and pick animations.
    func multiplier(for trait: PersonalityTrait) -> Double {
        0.7 + (self[trait] * 0.6)
    }

    mutating func move(_ trait: PersonalityTrait, to value: Double) {
        setRaw(trait, Personality.clamp(value))
    }

    /// Drifts a trait by at most `Personality.maxStepPerSettlement`.
    /// Returns the signed amount actually applied so the caller can log it.
    @discardableResult
    mutating func drift(_ trait: PersonalityTrait, towards target: Double, scale: Double = 1) -> Double {
        let current = self[trait]
        let gap = Personality.clamp(target) - current
        guard abs(gap) > 0.0001 else { return 0 }
        let step = min(abs(gap) * 0.25, Personality.maxStepPerSettlement) * max(0, min(1, scale))
        let applied = gap > 0 ? step : -step
        setRaw(trait, current + applied)
        return self[trait] - current
    }

    var isNeutral: Bool {
        PersonalityTrait.allCases.allSatisfy { abs(self[$0] - 0.5) < 0.02 }
    }

    private mutating func setRaw(_ trait: PersonalityTrait, _ value: Double) {
        switch trait {
        case .liveliness:   liveliness = value
        case .curiosity:    curiosity = value
        case .affection:    affection = value
        case .independence: independence = value
        case .laziness:     laziness = value
        }
    }

    private static func clamp(_ raw: Double) -> Double {
        guard raw.isFinite else { return 0.5 }
        return min(max(raw, 0), 1)
    }
}
