import Foundation

struct GrowthOutcome: Sendable {
    var previousLevel: Int = 1
    var newLevel: Int = 1
    var levelsGained: Int = 0
    var previousStage: GrowthStage = .hatchling
    var newStage: GrowthStage = .hatchling
    var unlockedItemIDs: [String] = []
    var experienceRemainder: Int = 0

    var didEvolve: Bool { newStage != previousStage }
}

/// Level curve and unlock table.
///
/// `PetState.experience` holds progress *inside the current level*, not lifetime
/// XP. That keeps the level-up loop trivial to reason about and means a level
/// can never disagree with the stored XP.
struct GrowthEngine: Sendable {
    static let maxLevel = 60

    /// XP required to move from `level` to `level + 1`.
    static func requirement(forLevel level: Int) -> Int {
        guard level < maxLevel else { return Int.max }
        return 40 + 20 * max(0, level - 1)
    }

    /// Cumulative XP needed to *reach* `level` from a fresh pet.
    static func totalXPNeeded(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return (1..<level).reduce(0) { $0 + requirement(forLevel: $1) }
    }

    static func level(forTotalXP xp: Int) -> Int {
        var level = 1
        var remaining = max(0, xp)
        while level < maxLevel && remaining >= requirement(forLevel: level) {
            remaining -= requirement(forLevel: level)
            level += 1
        }
        return level
    }

    /// Items granted automatically when a level is first reached.
    static let unlockTable: [Int: [String]] = [
        2:  ["furniture.lamp"],
        3:  ["food.crispbug"],
        5:  ["toy.glowring"],
        8:  ["bg.cavern"],
        10: ["acc.mosshat"],
        12: ["acc.starclip"],
        15: ["furniture.aquarium"],
        18: ["bg.sky", "room.sky"],
        25: ["acc.auroraribbon"],
        30: ["furniture.swing"]
    ]

    @discardableResult
    func apply(experience amount: Int, to pet: inout PetState) -> GrowthOutcome {
        var outcome = GrowthOutcome(
            previousLevel: pet.level,
            newLevel: pet.level,
            previousStage: pet.stage,
            newStage: pet.stage
        )
        guard amount > 0 else {
            outcome.experienceRemainder = pet.experience
            return outcome
        }

        pet.experience += amount

        while pet.level < Self.maxLevel,
              pet.experience >= Self.requirement(forLevel: pet.level) {
            pet.experience -= Self.requirement(forLevel: pet.level)
            pet.level += 1
            outcome.levelsGained += 1
            if let unlocks = Self.unlockTable[pet.level] {
                for itemID in unlocks where !pet.unlockedItemIDs.contains(itemID) {
                    pet.grantItem(itemID)
                    outcome.unlockedItemIDs.append(itemID)
                }
            }
        }

        // At the cap there is nowhere for the remainder to go.
        if pet.level >= Self.maxLevel {
            pet.experience = 0
        }

        outcome.newLevel = pet.level
        outcome.newStage = pet.stage
        outcome.experienceRemainder = pet.experience

        if outcome.didEvolve {
            pet.evolutionCount += 1
        }
        return outcome
    }

    func progressToNextLevel(for pet: PetState) -> Double {
        guard pet.level < Self.maxLevel else { return 1 }
        let need = Self.requirement(forLevel: pet.level)
        guard need > 0 else { return 1 }
        return min(1, max(0, Double(pet.experience) / Double(need)))
    }

    func experienceToNextLevel(for pet: PetState) -> Int {
        guard pet.level < Self.maxLevel else { return 0 }
        return max(0, Self.requirement(forLevel: pet.level) - pet.experience)
    }
}
