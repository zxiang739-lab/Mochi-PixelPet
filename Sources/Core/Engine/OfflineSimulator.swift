import Foundation

/// Tunable constants for offline simulation.
///
/// Everything time-based lives here rather than being sprinkled through the
/// code, which is what lets the test suite drive a 72-hour absence in
/// milliseconds and assert exact numbers.
struct SimulationTuning: Sendable {
    /// Wall-clock time beyond this is *not* simulated. A player returning after
    /// a month must not receive a month of events — that is the "有界结算" rule.
    var maxSettlementWindow: TimeInterval = 72 * 3600

    /// Simulation granularity. Smaller chunks give finer event timing at the
    /// cost of more iterations.
    var chunkDuration: TimeInterval = 30 * 60

    /// Hard cap on chunks regardless of window, so a pathological clock cannot
    /// turn one launch into a million iterations.
    var maxChunks: Int = 256

    var maxEventsPerSettlement: Int = 4
    var eventChancePerChunk: Double = 0.075

    /// Absences shorter than this produce no decay and no events — protecting
    /// against a launch storm (opening the app ten times a minute).
    var minimumElapsedForSimulation: TimeInterval = 90

    var satietyPerHour: Double = 4.2
    var energyPerHour: Double = 2.6
    var sleepRecoveryPerHour: Double = 9.5
    var cleanlinessPerHour: Double = 1.8
    var moodEaseRatePerHour: Double = 0.55
    var bondDecayPerDay: Double = 0.6

    static let standard = SimulationTuning()

    /// Compressed profile for UI tests so a flow does not have to wait 90s.
    static let fast = SimulationTuning(
        maxSettlementWindow: 72 * 3600,
        chunkDuration: 60,
        maxChunks: 256,
        maxEventsPerSettlement: 4,
        eventChancePerChunk: 0.6,
        minimumElapsedForSimulation: 1,
        satietyPerHour: 4.2,
        energyPerHour: 2.6,
        sleepRecoveryPerHour: 9.5,
        cleanlinessPerHour: 1.8,
        moodEaseRatePerHour: 0.55,
        bondDecayPerDay: 0.6
    )
}

struct SettlementResult: Sendable {
    /// Real elapsed time between the stored timestamp and now.
    var elapsed: TimeInterval = 0
    /// Elapsed time actually simulated (≤ `maxSettlementWindow`).
    var simulatedElapsed: TimeInterval = 0
    var wasCapped: Bool = false
    /// The clock moved backwards; elapsed was treated as zero.
    var clockWentBackwards: Bool = false

    var statDeltas = StatDeltas()
    var events: [ResolvedEvent] = []
    var behaviorBefore: BehaviorState = .idle
    var behaviorAfter: BehaviorState = .idle
    var completedActivity: ActiveActivity?
    var growth = GrowthOutcome()
    var didWakeUp: Bool = false
    var newDiaryEntries: [DiaryEntry] = []

    var hasMeaningfulChange: Bool {
        elapsed >= 60 || !events.isEmpty || completedActivity != nil || growth.levelsGained > 0
    }
}

/// Converts "time passed" into "the pet lived through it".
///
/// The whole design rests on one rule: **time is the only source of truth, and
/// it is consumed exactly once.** `lastSimulatedAt` is moved to `now` at the
/// start of every pass, before any work happens, so even a crash mid-settlement
/// cannot cause the same window to be paid twice — the worst case is losing that
/// window, which is the safe direction to fail in.
struct OfflineSimulator: Sendable {
    let tuning: SimulationTuning
    let events: EventEngine
    let personality: PersonalityEngine
    let growth: GrowthEngine

    init(
        tuning: SimulationTuning = .standard,
        events: EventEngine = EventEngine(),
        personality: PersonalityEngine = PersonalityEngine(),
        growth: GrowthEngine = GrowthEngine()
    ) {
        self.tuning = tuning
        self.events = events
        self.personality = personality
        self.growth = growth
    }

    func settle(
        _ pet: inout PetState,
        now: Date,
        rng: inout SeededGenerator
    ) -> SettlementResult {
        var result = SettlementResult()
        result.behaviorBefore = pet.behavior.state
        result.behaviorAfter = pet.behavior.state

        let rawElapsed = now.timeIntervalSince(pet.lastSimulatedAt)
        if rawElapsed < -1 {
            // Clock moved backwards (timezone abuse, restore from backup, manual
            // change). Never grant time, never go negative.
            result.clockWentBackwards = true
        }
        let elapsed = max(0, rawElapsed)
        result.elapsed = elapsed

        // Consume the window immediately. If anything below throws or the
        // process dies, we under-reward rather than double-reward.
        pet.lastSimulatedAt = now

        let statsBefore = pet.stats
        var pendingXP = 0

        // 1. Finish a timed activity if it has expired during the absence.
        if let activity = pet.activeActivity, activity.isFinished(at: now) {
            pendingXP += completeActivity(activity, pet: &pet, now: now, result: &result, rng: &rng)
        }

        // 2. Roll one-shot behaviour forward to whatever it settles into.
        advanceBehavior(&pet, now: now, result: &result)

        // 3. Simulate the absence in bounded chunks.
        let simulated = min(elapsed, tuning.maxSettlementWindow)
        result.simulatedElapsed = simulated
        result.wasCapped = simulated < elapsed

        if simulated >= tuning.minimumElapsedForSimulation {
            pendingXP += simulateAbsence(
                &pet,
                seconds: simulated,
                now: now,
                rng: &rng,
                result: &result
            )

            pet.counters.offlineSettlements += 1
            pet.counters.totalOfflineSeconds += elapsed
            updateStreak(&pet, now: now)
        }

        // 4. Personality drifts only when real time has passed.
        personality.applySlowDrift(to: &pet, elapsed: elapsed)

        // 5. Apply accumulated XP exactly once, through the growth engine.
        if pendingXP > 0 {
            let outcome = growth.apply(experience: pendingXP, to: &pet)
            result.growth = outcome
            if outcome.didEvolve {
                result.newDiaryEntries.append(
                    DiaryEntry.milestone(
                        petID: pet.id,
                        title: "进化 · \(outcome.newStage.displayName)",
                        body: "Mochi 长成了\(outcome.newStage.formName)。形状变了，但看你的时候还是同一个眼神。",
                        symbolName: "sparkles",
                        at: now
                    )
                )
            }
            if outcome.levelsGained > 0 && !outcome.unlockedItemIDs.isEmpty {
                for itemID in outcome.unlockedItemIDs {
                    guard let item = ItemCatalog.shared.item(itemID) else { continue }
                    result.newDiaryEntries.append(
                        DiaryEntry.milestone(
                            petID: pet.id,
                            title: "解锁 · \(item.name)",
                            body: item.detail,
                            symbolName: item.category.symbolName,
                            at: now,
                            category: .growth
                        )
                    )
                }
            }
        }

        result.statDeltas = Self.difference(from: statsBefore, to: pet.stats)
        result.behaviorAfter = pet.behavior.state
        return result
    }

    // MARK: - Steps

    private func advanceBehavior(
        _ pet: inout PetState,
        now: Date,
        result: inout SettlementResult
    ) {
        // Bounded loop: a corrupted timestamp could otherwise spin forever.
        var hops = 0
        while pet.behavior.isFinished(at: now), hops < 8 {
            let settledAt = pet.behavior.endsAt ?? now
            let next = pet.behavior.state.restingState
            pet.behavior = .make(next, at: settledAt)
            hops += 1
        }
        if hops == 8 {
            pet.behavior = BehaviorInstance(state: .idle, startedAt: now, endsAt: nil)
        }
    }

    private func completeActivity(
        _ activity: ActiveActivity,
        pet: inout PetState,
        now: Date,
        result: inout SettlementResult,
        rng: inout SeededGenerator
    ) -> Int {
        var xp = 0
        switch activity.kind {
        case .nap:
            pet.stats.energy.adjust(by: 35)
            pet.stats.mood.adjust(by: 4)
            pet.counters.sleepsCompleted += 1
            result.didWakeUp = true
            pet.behavior = BehaviorInstance.make(.wake, at: now)
            xp += 6

        case .explore:
            pet.counters.explorations += 1
            pet.stats.energy.adjust(by: -18)
            pet.stats.cleanliness.adjust(by: -12)
            if let definition = events.pickEvent(
                for: pet,
                at: now,
                offline: 0,
                excluding: Set(result.events.map(\.definitionID)),
                rng: &rng
            ) {
                let resolved = events.resolve(definition, for: &pet, at: now)
                result.events.append(resolved)
                result.newDiaryEntries.append(.from(resolved, petID: pet.id))
                xp += resolved.experience
            }
            xp += 10

        case .play:
            pet.stats.mood.adjust(by: 18)
            pet.stats.energy.adjust(by: -12)
            pet.stats.cleanliness.adjust(by: -6)
            pet.counters.plays += 1
            xp += 12
        }

        pet.activeActivity = nil
        result.completedActivity = activity
        result.behaviorAfter = pet.behavior.state
        return xp
    }

    private func simulateAbsence(
        _ pet: inout PetState,
        seconds: TimeInterval,
        now: Date,
        rng: inout SeededGenerator,
        result: inout SettlementResult
    ) -> Int {
        // Cap iterations explicitly: even if `seconds` is nonsense, the loop
        // count stays bounded.
        let rawChunks = Int((seconds / tuning.chunkDuration).rounded(.up))
        let chunkCount = max(1, min(rawChunks, tuning.maxChunks))
        let chunk = seconds / Double(chunkCount)
        let hoursPerChunk = chunk / 3600

        let startedAt = now.addingTimeInterval(-seconds)
        var firedIDs = Set(result.events.map(\.definitionID))
        var xp = 0

        for index in 0..<chunkCount {
            let chunkStart = startedAt.addingTimeInterval(Double(index) * chunk)
            let isSleeping = pet.behavior.state.isSleeping

            var deltas = StatDeltas()
            deltas.satiety = -tuning.satietyPerHour * hoursPerChunk
            deltas.cleanliness = -tuning.cleanlinessPerHour * hoursPerChunk
            deltas.energy = isSleeping
                ? tuning.sleepRecoveryPerHour * hoursPerChunk
                : -tuning.energyPerHour * hoursPerChunk
            if pet.stats.bond.value > 0 {
                deltas.bond = -tuning.bondDecayPerDay * (hoursPerChunk / 24)
            }
            pet.stats.apply(deltas)

            pet.stats.mood.ease(
                toward: Self.moodTarget(for: pet.stats),
                rate: tuning.moodEaseRatePerHour,
                over: chunk
            )

            // Exhaustion → involuntary sleep.
            if !isSleeping, pet.stats.energy.value <= 8, pet.activeActivity == nil {
                pet.behavior = BehaviorInstance(state: .sleep, startedAt: chunkStart, endsAt: nil)
                result.behaviorAfter = .sleep
            }

            // Recovered → wake up on its own.
            if pet.behavior.state.isSleeping, pet.stats.energy.isFull {
                pet.counters.sleepsCompleted += 1
                pet.behavior = BehaviorInstance.make(.wake, at: chunkStart)
                result.didWakeUp = true
                result.behaviorAfter = .wake
            }

            // Event roll. Capped per settlement so a long absence cannot
            // produce a wall of notifications.
            if result.events.count < tuning.maxEventsPerSettlement,
               rng.nextUnit() < tuning.eventChancePerChunk,
               let definition = events.pickEvent(
                   for: pet,
                   at: chunkStart,
                   offline: seconds,
                   excluding: firedIDs,
                   rng: &rng
               ) {
                let resolved = events.resolve(definition, for: &pet, at: chunkStart)
                firedIDs.insert(definition.id)
                result.events.append(resolved)
                result.newDiaryEntries.append(.from(resolved, petID: pet.id))
                xp += resolved.experience
            }
        }

        return xp
    }

    private func updateStreak(_ pet: inout PetState, now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let last = pet.lastVisitDay else {
            pet.streakDays = 1
            pet.lastVisitDay = today
            return
        }
        let gap = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        switch gap {
        case ..<1:  break                       // same day, no change
        case 1:     pet.streakDays += 1
        default:    pet.streakDays = 1
        }
        pet.lastVisitDay = today
    }

    // MARK: - Helpers

    /// Mood chases a value implied by how well the other needs are met, so a
    /// starving pet slowly becomes unhappy instead of dropping instantly.
    static func moodTarget(for stats: PetStats) -> Double {
        let base = stats.satiety.normalized * 0.35
            + stats.cleanliness.normalized * 0.20
            + stats.energy.normalized * 0.20
            + stats.bond.normalized * 0.25
        return 15 + base * 70
    }

    static func difference(from before: PetStats, to after: PetStats) -> StatDeltas {
        StatDeltas(
            satiety: after.satiety.value - before.satiety.value,
            mood: after.mood.value - before.mood.value,
            energy: after.energy.value - before.energy.value,
            cleanliness: after.cleanliness.value - before.cleanliness.value,
            bond: after.bond.value - before.bond.value
        )
    }
}
