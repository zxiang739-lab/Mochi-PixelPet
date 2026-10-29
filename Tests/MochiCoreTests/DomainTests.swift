import XCTest

final class BoundedStatTests: XCTestCase {
    func testClampsToRangeOnInit() {
        XCTAssertEqual(BoundedStat(140).value, 100, accuracy: 0.0001)
        XCTAssertEqual(BoundedStat(-40).value, 0, accuracy: 0.0001)
    }

    func testAdjustReportsAppliedDeltaNotRequestedDelta() {
        var stat = BoundedStat(95)
        let applied = stat.adjust(by: 20)
        XCTAssertEqual(applied, 5, accuracy: 0.0001, "only 5 of the requested 20 could land")
        XCTAssertEqual(stat.value, 100, accuracy: 0.0001)
    }

    func testNonFiniteDeltaIsIgnored() {
        var stat = BoundedStat(50)
        XCTAssertEqual(stat.adjust(by: .nan), 0)
        XCTAssertEqual(stat.adjust(by: .infinity), 0)
        XCTAssertEqual(stat.value, 50, accuracy: 0.0001)
    }

    func testEaseApproachesTargetWithoutOvershoot() {
        var stat = BoundedStat(0)
        stat.ease(toward: 100, rate: 0.5, over: 3600)
        XCTAssertGreaterThan(stat.value, 0)
        XCTAssertLessThanOrEqual(stat.value, 100)
    }

    func testEaseOverVeryLongWindowNeverExceedsTarget() {
        var stat = BoundedStat(0)
        stat.ease(toward: 100, rate: 0.5, over: 60 * 60 * 24 * 365)
        XCTAssertLessThanOrEqual(stat.value, 100.0)
    }
}

final class GrowthEngineTests: XCTestCase {
    let engine = GrowthEngine()

    func testLevelCurveIsMonotonic() {
        var previous = 0
        for level in 2...20 {
            let needed = GrowthEngine.totalXPNeeded(forLevel: level)
            XCTAssertGreaterThan(needed, previous, "cumulative XP must increase with level")
            previous = needed
        }
    }

    func testLevelRoundTripsThroughTotalXP() {
        for level in 1...20 {
            let total = GrowthEngine.totalXPNeeded(forLevel: level)
            XCTAssertEqual(GrowthEngine.level(forTotalXP: total), level)
        }
    }

    func testApplyingExperienceLevelsUpAndKeepsRemainder() {
        var pet = PetState(name: "Test", createdAt: Date())
        let outcome = engine.apply(experience: 200, to: &pet)

        XCTAssertGreaterThan(pet.level, 1)
        XCTAssertEqual(outcome.levelsGained, pet.level - 1)
        XCTAssertLessThan(pet.experience, GrowthEngine.requirement(forLevel: pet.level))
        XCTAssertGreaterThanOrEqual(pet.experience, 0)
    }

    func testEvolutionAtStageBoundary() {
        var pet = PetState(name: "Test", createdAt: Date())
        let outcome = engine.apply(
            experience: GrowthEngine.totalXPNeeded(forLevel: 10),
            to: &pet
        )
        XCTAssertEqual(pet.level, 10)
        XCTAssertEqual(pet.stage, .sproutling)
        XCTAssertTrue(outcome.didEvolve)
    }

    func testLevelCapIsRespected() {
        var pet = PetState(name: "Test", createdAt: Date())
        _ = engine.apply(experience: 10_000_000, to: &pet)
        XCTAssertEqual(pet.level, GrowthEngine.maxLevel)
    }
}

final class EventEngineTests: XCTestCase {
    let engine = EventEngine()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePet(level: Int = 5) -> PetState {
        var pet = PetState(name: "Test", createdAt: now.addingTimeInterval(-86_400))
        pet.level = level
        pet.stats = PetStats(satiety: 60, mood: 60, energy: 60, cleanliness: 60, bond: 30)
        return pet
    }

    func testCooldownBlocksAnEventThatJustFired() {
        var pet = makePet()
        let definition = EventCatalog.shared.event("ev.daily.sunbeam")!
        pet.eventCooldowns[definition.id] = now

        let eligible = engine.eligibleEvents(for: pet, at: now, offline: 0)
        XCTAssertFalse(eligible.contains { $0.id == definition.id })
    }

    func testCooldownExpiresAfterItsWindow() {
        var pet = makePet()
        let definition = EventCatalog.shared.event("ev.daily.sunbeam")!
        pet.eventCooldowns[definition.id] = now.addingTimeInterval(-definition.cooldown - 1)

        let eligible = engine.eligibleEvents(for: pet, at: now, offline: 0)
        XCTAssertTrue(eligible.contains { $0.id == definition.id })
    }

    func testLevelRequirementIsEnforced() {
        var pet = makePet(level: 1)
        let gated = EventCatalog.shared.event("ev.explore.starfall")!
        let eligible = engine.eligibleEvents(for: pet, at: now, offline: 0)
        XCTAssertFalse(eligible.contains { $0.id == gated.id })

        pet.level = 20
        let unlocked = engine.eligibleEvents(for: pet, at: now, offline: 0)
        XCTAssertTrue(unlocked.contains { $0.id == gated.id })
    }

    func testFestivalIsGatedOnCalendarMonth() {
        let definition = EventCatalog.shared.event("ev.festival.newyear")!
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        let july = Calendar.current.date(from: components)!
        components.month = 1
        let january = Calendar.current.date(from: components)!

        let pet = makePet()
        XCTAssertFalse(definition.requirements.isSatisfied(by: pet, offline: 0, now: july))
        XCTAssertTrue(definition.requirements.isSatisfied(by: pet, offline: 0, now: january))
    }

    func testResolveAppliesCooldownAndRewardsExactlyOnce() {
        var pet = makePet()
        let definition = EventCatalog.shared.event("ev.collect.shell")!
        let before = pet.count(of: "col.shell")

        let resolved = engine.resolve(definition, for: &pet, at: now)

        XCTAssertEqual(pet.count(of: "col.shell"), before + 1)
        XCTAssertEqual(pet.eventCooldowns[definition.id], now)
        XCTAssertTrue(pet.resolvedEventIDs.contains(definition.id))
        XCTAssertEqual(resolved.grantedItems.first?.itemID, "col.shell")
    }

    func testPickingIsDeterministicForAGivenSeed() {
        let pet = makePet()
        var seedA = SeededGenerator(seed: 12_345)
        var seedB = SeededGenerator(seed: 12_345)

        let first = engine.pickEvent(for: pet, at: now, offline: 0, rng: &seedA)
        let second = engine.pickEvent(for: pet, at: now, offline: 0, rng: &seedB)
        XCTAssertEqual(first?.id, second?.id)
    }
}

final class PersonalityEngineTests: XCTestCase {
    let engine = PersonalityEngine()

    func testNoDriftForShortAbsence() {
        var pet = PetState(name: "Test", createdAt: Date())
        pet.counters.plays = 40
        pet.counters.total = 40

        let moved = engine.applySlowDrift(to: &pet, elapsed: 60)
        XCTAssertTrue(moved.isEmpty)
        XCTAssertEqual(pet.personality[.liveliness], 0.5, accuracy: 0.0001)
    }

    func testDriftIsBoundedPerSettlement() {
        var pet = PetState(name: "Test", createdAt: Date())
        pet.counters.plays = 100
        pet.counters.total = 100

        _ = engine.applySlowDrift(to: &pet, elapsed: 3600)
        let afterOne = pet.personality[.liveliness]
        XCTAssertGreaterThan(afterOne, 0.5)
        XCTAssertLessThanOrEqual(afterOne - 0.5, Personality.maxStepPerSettlement + 0.0001)
    }

    func testHeavyPlayDoesNotMaxOutTrait() {
        var pet = PetState(name: "Test", createdAt: Date())
        pet.counters.plays = 1000
        pet.counters.total = 1000

        for _ in 0..<100 {
            _ = engine.applySlowDrift(to: &pet, elapsed: 3600)
        }
        XCTAssertLessThanOrEqual(pet.personality[.liveliness], 1.0)
    }

    func testIndependenceGrowsWithLongAbsences() {
        var pet = PetState(name: "Test", createdAt: Date())
        pet.counters.offlineSettlements = 10
        pet.counters.totalOfflineSeconds = 10 * 12 * 3600

        let targets = engine.targets(for: pet)
        XCTAssertGreaterThan(targets[.independence] ?? 0, 0.6)
    }
}
