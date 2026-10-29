import Foundation

/// The five live attributes plus the thresholds the rest of the app reasons about.
///
/// Nothing outside this file is allowed to write a raw number into a stat — the
/// `BoundedStat` setters are the only door, and every caller goes through
/// `adjust(by:)` so the applied delta can be reported back to the UI.
struct PetStats: Codable, Hashable, Sendable {
    var satiety: BoundedStat
    var mood: BoundedStat
    var energy: BoundedStat
    var cleanliness: BoundedStat
    var bond: BoundedStat

    init(
        satiety: Double = 70,
        mood: Double = 70,
        energy: Double = 80,
        cleanliness: Double = 85,
        bond: Double = 10
    ) {
        self.satiety = BoundedStat(satiety)
        self.mood = BoundedStat(mood)
        self.energy = BoundedStat(energy)
        self.cleanliness = BoundedStat(cleanliness)
        self.bond = BoundedStat(bond)
    }

    subscript(key: StatKey) -> BoundedStat {
        get {
            switch key {
            case .satiety:     satiety
            case .mood:        mood
            case .energy:      energy
            case .cleanliness: cleanliness
            case .bond:        bond
            }
        }
        set {
            switch key {
            case .satiety:     satiety = newValue
            case .mood:        mood = newValue
            case .energy:      energy = newValue
            case .cleanliness: cleanliness = newValue
            case .bond:        bond = newValue
            }
        }
    }

    /// Weighted average used by the widget and diary to pick an overall tone.
    var wellbeing: Double {
        (satiety.normalized * 0.25
         + mood.normalized * 0.25
         + energy.normalized * 0.2
         + cleanliness.normalized * 0.15
         + bond.normalized * 0.15) * 100
    }

    /// True when nothing is dangerously low — used to gate "happy" animations.
    var isComfortable: Bool {
        satiety.value >= 25 && mood.value >= 25 && energy.value >= 15 && cleanliness.value >= 20
    }

    /// The stat most in need of attention, driving the widget hint text.
    var mostUrgentNeed: StatKey? {
        let candidates: [(StatKey, Double)] = [
            (.satiety, satiety.value),
            (.energy, energy.value),
            (.cleanliness, cleanliness.value),
            (.mood, mood.value)
        ]
        guard let worst = candidates.min(by: { $0.1 < $1.1 }), worst.1 < 45 else { return nil }
        return worst.0
    }

    /// Applies a set of deltas and returns what actually landed after clamping.
    @discardableResult
    mutating func apply(_ deltas: StatDeltas) -> StatDeltas {
        var applied = StatDeltas()
        applied.satiety = satiety.adjust(by: deltas.satiety)
        applied.mood = mood.adjust(by: deltas.mood)
        applied.energy = energy.adjust(by: deltas.energy)
        applied.cleanliness = cleanliness.adjust(by: deltas.cleanliness)
        applied.bond = bond.adjust(by: deltas.bond)
        return applied
    }
}

enum StatKey: String, CaseIterable, Codable, Sendable {
    case satiety
    case mood
    case energy
    case cleanliness
    case bond

    var displayName: String {
        switch self {
        case .satiety:     "饱食度"
        case .mood:        "心情"
        case .energy:      "精力"
        case .cleanliness: "清洁度"
        case .bond:        "亲密度"
        }
    }

    var symbolName: String {
        switch self {
        case .satiety:     "fork.knife"
        case .mood:        "face.smiling"
        case .energy:      "bolt.fill"
        case .cleanliness: "bubbles.and.sparkles"
        case .bond:        "heart.fill"
        }
    }

    /// Colour ramp used by the glass meters.
    var tintHex: String {
        switch self {
        case .satiety:     "F2A65A"
        case .mood:        "F2C14E"
        case .energy:      "7FD8C4"
        case .cleanliness: "8FB8F0"
        case .bond:        "E8799B"
        }
    }
}

/// A transferable bundle of stat changes. Using a dedicated type instead of a
/// bare dictionary keeps every call site exhaustive and typo-proof.
struct StatDeltas: Codable, Hashable, Sendable {
    var satiety: Double = 0
    var mood: Double = 0
    var energy: Double = 0
    var cleanliness: Double = 0
    var bond: Double = 0

    var isEmpty: Bool {
        satiety == 0 && mood == 0 && energy == 0 && cleanliness == 0 && bond == 0
    }

    /// Non-zero changes, as identifiable items — Swift key paths cannot reach
    /// into tuples, so `ForEach` needs a struct rather than a raw pair.
    var nonZeroItems: [StatDeltaItem] {
        var items: [StatDeltaItem] = []
        if abs(satiety) > 0.01 { items.append(StatDeltaItem(key: .satiety, value: satiety)) }
        if abs(mood) > 0.01 { items.append(StatDeltaItem(key: .mood, value: mood)) }
        if abs(energy) > 0.01 { items.append(StatDeltaItem(key: .energy, value: energy)) }
        if abs(cleanliness) > 0.01 { items.append(StatDeltaItem(key: .cleanliness, value: cleanliness)) }
        if abs(bond) > 0.01 { items.append(StatDeltaItem(key: .bond, value: bond)) }
        return items
    }

    static func + (lhs: StatDeltas, rhs: StatDeltas) -> StatDeltas {
        StatDeltas(
            satiety: lhs.satiety + rhs.satiety,
            mood: lhs.mood + rhs.mood,
            energy: lhs.energy + rhs.energy,
            cleanliness: lhs.cleanliness + rhs.cleanliness,
            bond: lhs.bond + rhs.bond
        )
    }
}

struct StatDeltaItem: Identifiable, Hashable, Sendable {
    var id: String { key.rawValue }
    let key: StatKey
    let value: Double
}
