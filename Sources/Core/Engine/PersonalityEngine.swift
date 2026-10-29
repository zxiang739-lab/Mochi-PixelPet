import Foundation

/// A readable explanation of one personality dial. The spec demands that
/// personality changes be explainable, so every value ships with the evidence
/// that produced it rather than a bare number in a settings row.
struct PersonalityInsight: Sendable, Identifiable, Hashable {
    var id: String { trait.rawValue }
    let trait: PersonalityTrait
    let value: Double
    let headline: String
    let evidence: String
}

/// Drives personality from *lifetime behaviour shares*, not per-interaction
/// dice rolls.
///
/// The model is deliberately boring: each trait chases a target implied by the
/// player's long-run habits, moving at most `Personality.maxStepPerSettlement`
/// per settlement and only when meaningful wall-clock time has actually passed.
/// That combination makes it impossible to max a trait out in one afternoon,
/// and impossible for a single tap to move anything at all.
struct PersonalityEngine: Sendable {

    /// Below this, no drift happens — a player who opens the app five times in
    /// a minute should not see their pet change character.
    static let minimumElapsedForDrift: TimeInterval = 10 * 60

    func targets(for pet: PetState) -> [PersonalityTrait: Double] {
        let counters = pet.counters
        let total = Double(max(1, counters.total))

        let playShare = Double(counters.plays) / total
        let exploreShare = Double(counters.explorations) / total
        let petShare = Double(counters.pets) / total
        let restShare = Double(counters.rests) / total

        // 12h average absence = fully independent; 0h = fully clingy.
        let independenceTarget = 0.5 + (counters.averageOfflineHours / 12.0 - 0.25)

        return [
            .liveliness: Self.clamp01(0.5 + (playShare - 0.15) * 1.6),
            .curiosity: Self.clamp01(0.5 + (exploreShare - 0.10) * 1.8),
            .affection: Self.clamp01(0.5 + (petShare - 0.15) * 1.6),
            .laziness: Self.clamp01(0.5 + (restShare - 0.12) * 1.6),
            .independence: Self.clamp01(independenceTarget)
        ]
    }

    /// Applies bounded drift and returns what actually moved, for the diary.
    @discardableResult
    func applySlowDrift(to pet: inout PetState, elapsed: TimeInterval) -> [PersonalityTrait: Double] {
        guard elapsed >= Self.minimumElapsedForDrift else { return [:] }
        // A full hour of absence earns full step size; five minutes earns a
        // fraction of it.
        let scale = min(1.0, elapsed / 3600.0)
        let goals = targets(for: pet)

        var moved: [PersonalityTrait: Double] = [:]
        for trait in PersonalityTrait.allCases {
            guard let goal = goals[trait] else { continue }
            let delta = pet.personality.drift(trait, towards: goal, scale: scale)
            if abs(delta) > 0.0001 { moved[trait] = delta }
        }
        return moved
    }

    func insights(for pet: PetState) -> [PersonalityInsight] {
        PersonalityTrait.allCases
            .map { trait in
                PersonalityInsight(
                    trait: trait,
                    value: pet.personality[trait],
                    headline: Self.headline(for: trait, value: pet.personality[trait]),
                    evidence: Self.evidence(for: trait, pet: pet)
                )
            }
            .sorted { $0.value > $1.value }
    }

    /// One-sentence character summary used on the pet card.
    func summary(for pet: PetState) -> String {
        guard let dominant = pet.personality.dominant else {
            return "还在摸清自己是什么样的小家伙。"
        }
        switch dominant {
        case .liveliness:   return "一刻也停不下来，听到玩具的声音就冲过来。"
        case .curiosity:    return "什么都要闻一下、碰一下，柜子后面去过八次。"
        case .affection:    return "你坐下它就来，你起身它跟着，几乎没有距离感。"
        case .independence: return "自己待着也没问题，你回来时它才慢慢走过来。"
        case .laziness:     return "最喜欢的位置是垫子，第二喜欢的位置是另一个垫子。"
        }
    }

    // MARK: - Copy

    private static func headline(for trait: PersonalityTrait, value: Double) -> String {
        switch trait {
        case .liveliness:
            band(value, veryLow: "几乎不动", low: "偏安静", mid: "动得不勤",
                 high: "好动", veryHigh: "停不下来")
        case .curiosity:
            band(value, veryLow: "不太关心外面", low: "偏保守", mid: "偶尔看看",
                 high: "爱打听", veryHigh: "什么都想碰")
        case .affection:
            band(value, veryLow: "很有距离", low: "偏冷淡", mid: "看心情",
                 high: "黏人", veryHigh: "寸步不离")
        case .independence:
            band(value, veryLow: "离不开人", low: "偏依赖", mid: "能自己待着",
                 high: "独立", veryHigh: "完全自理")
        case .laziness:
            band(value, veryLow: "闲不住", low: "偏勤快", mid: "动静各半",
                 high: "爱躺", veryHigh: "长在垫子上")
        }
    }

    private static func band(
        _ value: Double,
        veryLow: String,
        low: String,
        mid: String,
        high: String,
        veryHigh: String
    ) -> String {
        switch value {
        case ..<0.30: veryLow
        case ..<0.45: low
        case ..<0.58: mid
        case ..<0.75: high
        default:      veryHigh
        }
    }

    private static func evidence(for trait: PersonalityTrait, pet: PetState) -> String {
        let c = pet.counters
        switch trait {
        case .liveliness:
            return "玩耍 \(c.plays) 次 / 总互动 \(c.total) 次"
        case .curiosity:
            return "探索 \(c.explorations) 次"
        case .affection:
            return "抚摸 \(c.pets) 次，亲密度 \(Int(pet.stats.bond.value))"
        case .independence:
            return String(format: "平均离开 %.1f 小时", c.averageOfflineHours)
        case .laziness:
            return "休息 \(c.rests) 次，睡满 \(c.sleepsCompleted) 次"
        }
    }

    private static func clamp01(_ x: Double) -> Double {
        guard x.isFinite else { return 0.5 }
        return min(max(x, 0), 1)
    }
}
