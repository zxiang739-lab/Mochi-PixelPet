import Foundation

enum EventCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case exploration
    case collectible
    case toyDiscovery
    case specialInteraction
    case festival
    case growth
    case hidden
    case dailyLife

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exploration:        "探索发现"
        case .collectible:        "收藏"
        case .toyDiscovery:       "新玩具"
        case .specialInteraction: "特别互动"
        case .festival:           "节日"
        case .growth:             "成长"
        case .hidden:             "隐藏"
        case .dailyLife:          "日常"
        }
    }

    var symbolName: String {
        switch self {
        case .exploration:        "map.fill"
        case .collectible:        "seal.fill"
        case .toyDiscovery:       "tennisball.fill"
        case .specialInteraction: "sparkles"
        case .festival:           "fireworks"
        case .growth:             "arrow.up.heart.fill"
        case .hidden:             "eye.trianglebadge.exclamationmark.fill"
        case .dailyLife:          "leaf.fill"
        }
    }
}

/// Declarative trigger conditions.
///
/// Deliberately data rather than closures: a struct like this can be inspected,
/// diffed in a debug screen, asserted against in tests, and — most importantly —
/// explained to the player ("需要亲密度 40 以上"), which a black-box predicate
/// cannot.
struct EventRequirements: Sendable, Hashable {
    var minLevel: Int = 1
    var maxLevel: Int = Int.max
    var stages: Set<GrowthStage> = []
    var minBond: Double = 0
    var minSatiety: Double = 0
    var maxSatiety: Double = 100
    var minEnergy: Double = 0
    var maxEnergy: Double = 100
    var minMood: Double = 0
    var maxMood: Double = 100
    var minExplorations: Int = 0
    var requiresSleeping: Bool = false
    var requiresAwake: Bool = false
    /// Trait → minimum value the pet must have reached.
    var minTraits: [PersonalityTrait: Double] = [:]
    /// Only fires after the player has been away at least this long.
    var minimumOffline: TimeInterval = 0
    /// Calendar gates for festivals. Empty means "any month".
    var allowedMonths: Set<Int> = []
    /// Hour-of-day gates for late-night or early-morning events. Empty means any.
    var allowedHours: Set<Int> = []

    func isSatisfied(by pet: PetState, offline: TimeInterval, now: Date) -> Bool {
        let calendar = Calendar.current
        if !allowedMonths.isEmpty,
           !allowedMonths.contains(calendar.component(.month, from: now)) {
            return false
        }
        if !allowedHours.isEmpty,
           !allowedHours.contains(calendar.component(.hour, from: now)) {
            return false
        }
        if pet.level < minLevel || pet.level > maxLevel { return false }
        if !stages.isEmpty && !stages.contains(pet.stage) { return false }
        if pet.stats.bond.value < minBond { return false }
        if pet.stats.satiety.value < minSatiety || pet.stats.satiety.value > maxSatiety { return false }
        if pet.stats.energy.value < minEnergy || pet.stats.energy.value > maxEnergy { return false }
        if pet.stats.mood.value < minMood || pet.stats.mood.value > maxMood { return false }
        if pet.counters.explorations < minExplorations { return false }
        if requiresSleeping && !pet.behavior.state.isSleeping { return false }
        if requiresAwake && pet.behavior.state.isSleeping { return false }
        if offline < minimumOffline { return false }
        for (trait, threshold) in minTraits where pet.personality[trait] < threshold {
            return false
        }
        return true
    }

    /// Human-readable list of unmet conditions, used by the (hidden) event
    /// debug screen and by tests that assert eligibility boundaries.
    func unmetConditions(for pet: PetState, offline: TimeInterval, now: Date) -> [String] {
        var reasons: [String] = []
        let calendar = Calendar.current
        if !allowedMonths.isEmpty,
           !allowedMonths.contains(calendar.component(.month, from: now)) {
            reasons.append("仅限 \(allowedMonths.sorted().map(String.init).joined(separator: "/")) 月")
        }
        if !allowedHours.isEmpty,
           !allowedHours.contains(calendar.component(.hour, from: now)) {
            reasons.append("仅限 \(allowedHours.sorted().map(String.init).joined(separator: "/")) 点")
        }
        if pet.level < minLevel { reasons.append("等级需 \(minLevel)") }
        if pet.level > maxLevel { reasons.append("等级需 ≤ \(maxLevel)") }
        if !stages.isEmpty && !stages.contains(pet.stage) {
            reasons.append("形态需为 \(stages.map(\.displayName).sorted().joined(separator: "/"))")
        }
        if pet.stats.bond.value < minBond { reasons.append("亲密度需 \(Int(minBond))") }
        if pet.stats.satiety.value < minSatiety { reasons.append("饱食度需 ≥ \(Int(minSatiety))") }
        if pet.stats.satiety.value > maxSatiety { reasons.append("饱食度需 ≤ \(Int(maxSatiety))") }
        if pet.stats.energy.value < minEnergy { reasons.append("精力需 ≥ \(Int(minEnergy))") }
        if pet.stats.energy.value > maxEnergy { reasons.append("精力需 ≤ \(Int(maxEnergy))") }
        if pet.stats.mood.value < minMood { reasons.append("心情需 ≥ \(Int(minMood))") }
        if pet.stats.mood.value > maxMood { reasons.append("心情需 ≤ \(Int(maxMood))") }
        if pet.counters.explorations < minExplorations { reasons.append("探索次数需 \(minExplorations)") }
        if requiresSleeping && !pet.behavior.state.isSleeping { reasons.append("需要睡着") }
        if requiresAwake && pet.behavior.state.isSleeping { reasons.append("需要醒着") }
        if offline < minimumOffline { reasons.append("需离开 \(Int(minimumOffline / 60)) 分钟以上") }
        for (trait, threshold) in minTraits where pet.personality[trait] < threshold {
            reasons.append("\(trait.displayName)需 \(Int(threshold * 100))")
        }
        return reasons
    }
}

struct ItemReward: Sendable, Hashable, Codable {
    let itemID: String
    let count: Int

    init(_ itemID: String, _ count: Int = 1) {
        self.itemID = itemID
        self.count = count
    }
}

struct PetEventDefinition: Identifiable, Sendable {
    let id: String
    let category: EventCategory
    let title: String
    /// Diary prose shown in the 日记 tab. Second person, past tense — it should
    /// read like something that happened, not a system message.
    let diaryText: String
    let requirements: EventRequirements
    /// Relative selection weight. Combined with personality multipliers by the
    /// engine, so a curious Mochi finds more exploration events without the
    /// catalogue needing a special case.
    let weight: Double
    /// Seconds before this specific event may fire again.
    let cooldown: TimeInterval
    let effects: StatDeltas
    let rewards: [ItemReward]
    let experience: Int
    let animation: BehaviorState?
    let isHidden: Bool

    init(
        id: String,
        category: EventCategory,
        title: String,
        diaryText: String,
        requirements: EventRequirements = EventRequirements(),
        weight: Double = 1,
        cooldown: TimeInterval = 3600,
        effects: StatDeltas = StatDeltas(),
        rewards: [ItemReward] = [],
        experience: Int = 5,
        animation: BehaviorState? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.diaryText = diaryText
        self.requirements = requirements
        self.weight = weight
        self.cooldown = cooldown
        self.effects = effects
        self.rewards = rewards
        self.experience = experience
        self.animation = animation
        self.isHidden = isHidden
    }
}

/// The outcome of one event actually firing. Carries the applied (post-clamp)
/// stat deltas so the UI can show "+12 心情" that is truthful even when the bar
/// was already at 96.
struct ResolvedEvent: Sendable, Identifiable, Hashable {
    var id: String { definitionID + "@" + String(timestamp.timeIntervalSince1970) }
    let definitionID: String
    let title: String
    let body: String
    let category: EventCategory
    let symbolName: String
    let timestamp: Date
    let appliedEffects: StatDeltas
    let grantedItems: [ItemReward]
    let experience: Int
    let animation: BehaviorState?
    let isMilestone: Bool
}
