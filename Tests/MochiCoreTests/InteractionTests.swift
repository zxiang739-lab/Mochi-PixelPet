import XCTest

final class InteractionServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var service = InteractionService()

    private func makePet() -> PetState {
        PetState(name: "Test", createdAt: now.addingTimeInterval(-3600))
    }

    // MARK: - Feeding

    func testFeedingConsumesOneItemAndRecordsTheAction() throws {
        var pet = makePet()
        let before = pet.count(of: "food.berry")

        let receipt = try service.feed(itemID: "food.berry", pet: &pet, now: now)

        XCTAssertEqual(pet.count(of: "food.berry"), before - 1)
        XCTAssertEqual(pet.counters.feeds, 1)
        XCTAssertEqual(receipt.behavior, .eat)
        XCTAssertGreaterThan(pet.stats.satiety.value, 70)
    }

    func testFeedingTwiceImmediatelyIsRejectedByCooldown() throws {
        var pet = makePet()
        _ = try service.feed(itemID: "food.berry", pet: &pet, now: now)

        XCTAssertThrowsError(try service.feed(itemID: "food.berry", pet: &pet, now: now.addingTimeInterval(0.5))) { error in
            guard let failure = error as? InteractionFailure else {
                return XCTFail("expected InteractionFailure")
            }
            XCTAssertNotNil(failure.retryAfter)
        }
        XCTAssertEqual(pet.counters.feeds, 1, "the rejected attempt must not count")
    }

    func testFeedingAfterCooldownSucceeds() throws {
        var pet = makePet()
        _ = try service.feed(itemID: "food.berry", pet: &pet, now: now)
        _ = try service.feed(itemID: "food.berry", pet: &pet, now: now.addingTimeInterval(30))
        XCTAssertEqual(pet.counters.feeds, 2)
    }

    func testFeedingAnEmptySlotFails() {
        var pet = makePet()
        pet.inventory.removeValue(forKey: "food.berry")

        XCTAssertThrowsError(try service.feed(itemID: "food.berry", pet: &pet, now: now))
    }

    func testFeedingASleepingPetIsRejected() {
        var pet = makePet()
        pet.behavior = BehaviorInstance(state: .sleep, startedAt: now, endsAt: nil)

        XCTAssertThrowsError(try service.feed(itemID: "food.berry", pet: &pet, now: now))
    }

    func testFeedingWhenAlreadyFullIsRejected() {
        var pet = makePet()
        pet.stats.satiety = BoundedStat(100)

        XCTAssertThrowsError(try service.feed(itemID: "food.berry", pet: &pet, now: now))
    }

    func testFeedingAnUnknownItemFails() {
        var pet = makePet()
        XCTAssertThrowsError(try service.feed(itemID: "food.nope", pet: &pet, now: now))
    }

    func testFeedingAToyIsRejected() {
        var pet = makePet()
        pet.grantItem("toy.leafball")
        XCTAssertThrowsError(try service.feed(itemID: "toy.leafball", pet: &pet, now: now))
    }

    // MARK: - Play / rest / clean

    func testPlayingRequiresEnergy() {
        var pet = makePet()
        pet.stats.energy = BoundedStat(4)
        XCTAssertThrowsError(try service.play(toyID: "toy.leafball", pet: &pet, now: now))
    }

    func testPlayingDrainsEnergyAndLiftsMood() throws {
        var pet = makePet()
        let energyBefore = pet.stats.energy.value
        let moodBefore = pet.stats.mood.value

        _ = try service.play(toyID: "toy.leafball", pet: &pet, now: now)

        XCTAssertLessThan(pet.stats.energy.value, energyBefore)
        XCTAssertGreaterThan(pet.stats.mood.value, moodBefore)
        XCTAssertEqual(pet.counters.plays, 1)
    }

    func testRestStartsANapActivity() throws {
        var pet = makePet()
        let receipt = try service.rest(pet: &pet, now: now)

        XCTAssertEqual(pet.activeActivity?.kind, .nap)
        XCTAssertEqual(receipt.startedActivity?.kind, .nap)
        XCTAssertTrue(pet.behavior.state.isSleeping)
    }

    func testRestingTwiceIsRejected() throws {
        var pet = makePet()
        _ = try service.rest(pet: &pet, now: now)
        XCTAssertThrowsError(try service.rest(pet: &pet, now: now.addingTimeInterval(60)))
    }

    func testCleaningPrefersSoapThenFallsBackToBrush() throws {
        var pet = makePet()
        pet.stats.cleanliness = BoundedStat(20)

        let first = try service.clean(pet: &pet, now: now)
        XCTAssertEqual(first.consumedItems.first?.itemID, "care.soap")

        pet.grantItem("care.brush")
        let second = try service.clean(pet: &pet, now: now.addingTimeInterval(60))
        XCTAssertTrue(second.consumedItems.isEmpty, "the brush is reusable")
    }

    func testCleaningWithoutToolsFails() {
        var pet = makePet()
        pet.inventory.removeValue(forKey: "care.soap")
        XCTAssertThrowsError(try service.clean(pet: &pet, now: now))
    }

    // MARK: - Exploration

    func testExplorationCannotStartWhileBusy() throws {
        var pet = makePet()
        _ = try service.startExploration(pet: &pet, now: now)
        XCTAssertThrowsError(
            try service.startExploration(pet: &pet, now: now.addingTimeInterval(120))
        )
    }

    func testExplorationNeedsEnergy() {
        var pet = makePet()
        pet.stats.energy = BoundedStat(5)
        XCTAssertThrowsError(try service.startExploration(pet: &pet, now: now))
    }

    func testPettingAWakingPetHasNoPenalty() throws {
        var pet = makePet()
        let receipt = try service.petting(pet: &pet, now: now)
        XCTAssertGreaterThan(receipt.appliedDeltas.bond, 0)
    }

    func testPettingASleepingPetWakesItWithAMoodPenalty() throws {
        var pet = makePet()
        pet.behavior = BehaviorInstance(state: .sleep, startedAt: now, endsAt: nil)
        let moodBefore = pet.stats.mood.value

        let receipt = try service.petting(pet: &pet, now: now)

        XCTAssertFalse(pet.behavior.state.isSleeping)
        XCTAssertLessThan(receipt.appliedDeltas.mood, 0)
        XCTAssertLessThan(pet.stats.mood.value, moodBefore)
    }
}

final class SnapshotStoreTests: XCTestCase {
    func testRoundTripPreservesFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SnapshotStore(directory: directory)

        let snapshot = PetSnapshot(
            petID: UUID(),
            name: "Mochi",
            level: 12,
            stage: .bloomtail,
            behavior: .sleep,
            mood: 42,
            energy: 61,
            satiety: 33,
            bond: 77,
            companionDays: 30,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            nextChangeAt: Date(timeIntervalSince1970: 1_700_003_600)
        )

        XCTAssertTrue(store.save(snapshot))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.petID, snapshot.petID)
        XCTAssertEqual(loaded.stage, .bloomtail)
        XCTAssertEqual(loaded.behavior, .sleep)
        XCTAssertEqual(loaded.level, 12)
        XCTAssertEqual(loaded.mood, 42, accuracy: 0.001)

        store.clear()
        XCTAssertNil(store.load())
    }

    func testMissingFileReturnsNilRatherThanThrowing() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        XCTAssertNil(SnapshotStore(directory: directory).load())
    }

    func testSchemaMismatchIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SnapshotStore(directory: directory)
        var snapshot = PetSnapshot.placeholder(now: Date())
        snapshot.schemaVersion = PetSnapshot.currentSchemaVersion + 1

        XCTAssertTrue(store.save(snapshot))
        XCTAssertNil(store.load(), "a future schema must not be silently consumed")
    }
}
