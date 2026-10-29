import Foundation

/// Picks and applies random events.
///
/// Two invariants the product spec calls out explicitly, both enforced here:
///   1. An event whose cooldown has not elapsed cannot fire.
///   2. The same event cannot fire twice inside a single settlement pass —
///      enforced by the caller tracking `alreadyFired` and by `resolve` setting
///      the cooldown *before* returning.
struct EventEngine: Sendable {
    let catalog: EventCatalog

    init(catalog: EventCatalog = .shared) {
        self.catalog = catalog
    }

    /// Events whose requirements and cooldowns are currently satisfied.
    func eligibleEvents(
        for pet: PetState,
        at now: Date,
        offline: TimeInterval
    ) -> [PetEventDefinition] {
        catalog.events.filter { definition in
            guard definition.requirements.isSatisfied(by: pet, offline: offline, now: now) else {
                return false
            }
            if let last = pet.eventCooldowns[definition.id],
               now.timeIntervalSince(last) < definition.cooldown {
                return false
            }
            return true
        }
    }

    /// Personality tilts the odds without ever making an event impossible:
    /// a multiplier of 1.3 is a nudge, not a switch.
    func effectiveWeight(of definition: PetEventDefinition, for pet: PetState) -> Double {
        let trait = Self.biasTrait(for: definition.category)
        let multiplier = trait.map { pet.personality.multiplier(for: $0) } ?? 1.0
        return max(0.001, definition.weight * multiplier)
    }

    static func biasTrait(for category: EventCategory) -> PersonalityTrait? {
        switch category {
        case .exploration:        .curiosity
        case .collectible:        .curiosity
        case .toyDiscovery:       .liveliness
        case .specialInteraction: .affection
        case .growth:             .liveliness
        case .hidden:             .independence
        case .dailyLife:          .laziness
        case .festival:           nil
        }
    }

    /// Weighted pick. Returns `nil` when nothing is eligible.
    func pickEvent(
        for pet: PetState,
        at now: Date,
        offline: TimeInterval,
        excluding alreadyFired: Set<String> = [],
        rng: inout SeededGenerator
    ) -> PetEventDefinition? {
        let candidates = eligibleEvents(for: pet, at: now, offline: offline)
            .filter { !alreadyFired.contains($0.id) }
        guard !candidates.isEmpty else { return nil }

        let weights = candidates.map { effectiveWeight(of: $0, for: pet) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }

        var roll = rng.nextUnit() * total
        for (definition, weight) in zip(candidates, weights) {
            roll -= weight
            if roll <= 0 { return definition }
        }
        return candidates.last
    }

    /// Applies an event's effects, rewards, XP and cooldown, returning the
    /// record used to write a diary entry.
    ///
    /// Stat deltas reported back are the *applied* deltas after clamping, so a
    /// pet already at 100 mood does not claim "+12 心情" in the diary.
    @discardableResult
    func resolve(
        _ definition: PetEventDefinition,
        for pet: inout PetState,
        at now: Date
    ) -> ResolvedEvent {
        let applied = pet.stats.apply(definition.effects)

        for reward in definition.rewards {
            pet.grantItem(reward.itemID, count: reward.count)
        }

        // Experience is intentionally *not* applied here. `PetState.experience`
        // is progress inside the current level, so only `GrowthEngine` may add
        // to it — otherwise XP could pile up past a threshold without ever
        // levelling the pet up.

        pet.eventCooldowns[definition.id] = now
        pet.resolvedEventIDs.insert(definition.id)

        if let animation = definition.animation, pet.behavior.state.isInterruptible {
            pet.behavior = .make(animation, at: now)
        }

        return ResolvedEvent(
            definitionID: definition.id,
            title: definition.title,
            body: definition.diaryText,
            category: definition.category,
            symbolName: definition.category.symbolName,
            timestamp: now,
            appliedEffects: applied,
            grantedItems: definition.rewards,
            experience: definition.experience,
            animation: definition.animation,
            isMilestone: definition.category == .growth
        )
    }

    /// Debug/preview helper: what *could* happen right now, and why not.
    func debugCandidates(for pet: PetState, at now: Date, offline: TimeInterval)
        -> [(id: String, eligible: Bool, reasons: [String])] {
        catalog.events.map { definition in
            let reasons = definition.requirements.unmetConditions(for: pet, offline: offline, now: now)
            var blocked = reasons
            if let last = pet.eventCooldowns[definition.id],
               now.timeIntervalSince(last) < definition.cooldown {
                let remaining = definition.cooldown - now.timeIntervalSince(last)
                blocked.append("冷却中 剩余 \(Int(remaining / 60)) 分钟")
            }
            return (definition.id, blocked.isEmpty, blocked)
        }
    }
}
