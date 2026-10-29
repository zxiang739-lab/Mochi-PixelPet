import XCTest

/// These are the tests that matter most: the offline simulation is where the
/// product is easiest to get subtly wrong, so each failure mode the spec calls
/// out has an explicit assertion here.
final class OfflineSettlementTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePet() -> PetState {
        PetState(name: "Test", createdAt: start)
    }

    private func simulator(_ tuning: SimulationTuning = .standard) -> OfflineSimulator {
        OfflineSimulator(tuning: tuning)
    }

    // MARK: - The same window is never paid twice

    func testSecondSettlementOfSameInstantIsANoOp() {
        var pet = makePet()
        var rng = SeededGenerator(seed: 7)
        let sim = simulator()

        let arrival = start.addingTimeInterval(3600)
        _ = sim.settle(&pet, now: arrival, rng: &rng)
        let satietyAfterFirst = pet.stats.satiety.value
        let levelAfterFirst = pet.level

        let second = sim.settle(&pet, now: arrival, rng: &rng)

        XCTAssertEqual(second.elapsed, 0, accuracy: 0.001)
        XCTAssertEqual(pet.stats.satiety.value, satietyAfterFirst, accuracy: 0.0001)
        XCTAssertEqual(pet.level, levelAfterFirst)
        XCTAssertTrue(second.events.isEmpty)
    }

    func testRepeatedLaunchesInQuickSuccessionDoNotDrainStats() {
        var pet = makePet()
        var rng = SeededGenerator(seed: 11)
        let sim = simulator()
        let before = pet.stats.satiety.value

        // Ten launches inside the minimum-elapsed guard.
        for i in 1...10 {
            _ = sim.settle(&pet, now: start.addingTimeInterval(Double(i) * 3), rng: &rng)
        }

        XCTAssertEqual(pet.stats.satiety.value, before, accuracy: 0.0001)
    }

    // MARK: - Clock abuse

    func testClockMovingBackwardsGrantsNothing() {
        var pet = makePet()
        var rng = SeededGenerator(seed: 3)
        let sim = simulator()
        let before = pet.stats.satiety.value

        let result = sim.settle(&pet, now: start.addingTimeInterval(-7200), rng: &rng)

        XCTAssertTrue(result.clockWentBackwards)
        XCTAssertEqual(result.elapsed, 0, accuracy: 0.001)
        XCTAssertEqual(pet.stats.satiety.value, before, accuracy: 0.0001)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testClockRestoredAfterRewindDoesNotDoubleReward() {
        var pet = makePet()
        var rng = SeededGenerator(seed: 5)
        let sim = simulator()

        _ = sim.settle(&pet, now: start.addingTimeInterval(3600), rng: &rng)
        let afterNormal = pet.stats.satiety.value

        // User drags the clock back an hour, then forward again.
        _ = sim.settle(&pet, now: start, rng: &rng)
        _ = sim.settle(&pet, now: start.addingTimeInterval(3600), rng: &rng)

        XCTAssertLessThanOrEqual(pet.stats.satiety.value, afterNormal + 0.001)
    }

    // MARK: - Bounded settlement

    func testLongAbsenceIsCappedToTheSimulationWindow() {
        var pet = makePet()
        var rng = SeededGenerator(seed: 9)
        let sim = simulator()

        let result = sim.settle(&pet, now: start.addingTimeInterval(30 * 24 * 3600), rng: &rng)

        XCTAssertTrue(result.wasCapped)
        XCTAssertEqual(result.simulatedElapsed, 72 * 3600, accuracy: 1)
        XCTAssertGreaterThan(result.elapsed, 72 * 3600)
    }

    func testEventCountPerSettlementIsCapped() {
        var pet = makePet()
        pet.level = 40
        pet.stats = PetStats(satiety: 90, mood: 90, energy: 90, cleanliness: 90, bond: 90)

        var rng = SeededGenerator(seed: 2024)
        let tuning = SimulationTuning.standard
        let result = simulator(tuning).settle(
            &pet,
            now: start.addingTimeInterval(72 * 3600),
            rng: &rng
        )

        XCTAssertLessThanOrEqual(result.events.count, tuning.maxEventsPerSettlement)
    }

    func testNoEventFiresTwiceWithinOneSettlement() {
        var pet = makePet()
        pet.level = 40
        var rng = SeededGenerator(seed: 4242)

        let result = simulator().settle(
            &pet,
            now: start.addingTimeInterval(72 * 3600),
            rng: &rng
        )

        let ids = result.events.map(\.definitionID)
        XCTAssertEqual(ids.count, Set(ids).count, "an event must not double-dip in one pass")
    }

    // MARK: - Stats stay legal

    func testStatsNeverLeaveTheirRangeAfterExtremeAbsence() {
        var pet = makePet()
        var rng = SeededGenerator(seed: 1)
        _ = simulator().settle(&pet, now: start.addingTimeInterval(365 * 24 * 3600), rng: &rng)

        for key in StatKey.allCases {
            let value = pet.stats[key].value
            XCTAssertGreaterThanOrEqual(value, 0, "\(key) underflowed")
            XCTAssertLessThanOrEqual(value, 100, "\(key) overflowed")
        }
    }

    func testHungerDropsOverADayButStaysLegal() {
        var pet = makePet()
        var rng = SeededGenerator(seed: 8)
        let before = pet.stats.satiety.value

        _ = simulator().settle(&pet, now: start.addingTimeInterval(24 * 3600), rng: &rng)

        XCTAssertLessThan(pet.stats.satiety.value, before)
        XCTAssertGreaterThanOrEqual(pet.stats.satiety.value, 0)
    }

    // MARK: - Behaviour and activities

    func testFinishedOneShotBehaviourSettlesToItsRestingState() {
        var pet = makePet()
        pet.behavior = .make(.eat, at: start)
        var rng = SeededGenerator(seed: 2)

        let result = simulator().settle(
            &pet,
            now: start.addingTimeInterval(10),
            rng: &rng
        )

        XCTAssertNotEqual(result.behaviorAfter, .eat)
    }

    func testCompletedExplorationIsRewardedOnce() {
        var pet = makePet()
        let activity = ActiveActivity(
            id: UUID(),
            kind: .explore,
            startedAt: start,
            endsAt: start.addingTimeInterval(60)
        )
        pet.activeActivity = activity
        var rng = SeededGenerator(seed: 77)

        let first = simulator().settle(
            &pet,
            now: start.addingTimeInterval(120),
            rng: &rng
        )
        XCTAssertEqual(first.completedActivity?.id, activity.id)
        XCTAssertNil(pet.activeActivity)

        let explorations = pet.counters.explorations

        let second = simulator().settle(
            &pet,
            now: start.addingTimeInterval(130),
            rng: &rng
        )
        XCTAssertNil(second.completedActivity)
        XCTAssertEqual(pet.counters.explorations, explorations)
    }

    func testOfflineCountersAccumulateOncePerSettlement() {
        var pet = makePet()
        var rng = SeededGenerator(seed: 6)
        let sim = simulator()

        _ = sim.settle(&pet, now: start.addingTimeInterval(3600), rng: &rng)
        XCTAssertEqual(pet.counters.offlineSettlements, 1)

        _ = sim.settle(&pet, now: start.addingTimeInterval(7200), rng: &rng)
        XCTAssertEqual(pet.counters.offlineSettlements, 2)
    }
}
