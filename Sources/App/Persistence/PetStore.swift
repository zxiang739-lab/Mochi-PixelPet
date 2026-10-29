import Foundation
import Observation
import SwiftData
import SwiftUI
import WidgetKit

/// Everything the UI is allowed to talk to.
///
/// One observable object owns the pet, mediates every mutation through
/// `InteractionService` / `OfflineSimulator`, and is the single place that
/// writes to SwiftData, the App Group snapshot and WidgetKit. Views are pure
/// functions of this state — they never mutate a `PetState` themselves.
@MainActor
@Observable
final class PetStore {

    // MARK: - Observable state

    private(set) var pet: PetState
    private(set) var diary: [DiaryEntry] = []
    private(set) var lastSettlement: SettlementResult?
    private(set) var toast: Toast?
    private(set) var isReady = false
    /// True when the App Group container was unavailable, so the widget shows
    /// placeholder data. Surfaced honestly in Settings instead of pretending.
    private(set) var isWidgetDataShared: Bool

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isFailure: Bool
    }

    // MARK: - Collaborators

    private let context: ModelContext
    private let clock: GameClock
    private var simulator: OfflineSimulator
    private var interactions: InteractionService
    private let snapshots: SnapshotStore
    private let liveActivity = LiveActivityManager()
    private let notifications = NotificationScheduler()
    private var record: PetRecord?

    // MARK: - Init

    init(context: ModelContext, clock: GameClock = SystemClock(), tuning: SimulationTuning = .standard) {
        self.context = context
        self.clock = clock
        self.snapshots = SnapshotStore()
        self.isWidgetDataShared = SnapshotStore().isShared
        self.simulator = OfflineSimulator(tuning: tuning)
        self.interactions = InteractionService(tuning: tuning)

        let loaded = PetStore.loadOrCreatePet(in: context, now: clock.now)
        self.pet = loaded.pet
        self.record = loaded.record
        self.diary = PetStore.loadDiary(in: context, petID: loaded.pet.id)
    }

    // MARK: - Lifecycle

    /// Runs the offline settlement. Safe to call repeatedly: the simulator moves
    /// its own watermark, so a second call in the same second is a no-op.
    func activate() {
        let now = clock.now
        var rng = SeededGenerator(petID: pet.id, timestamp: pet.lastSimulatedAt)
        var working = pet
        let result = simulator.settle(&working, now: now, rng: &rng)

        pet = working
        lastSettlement = result

        if result.hasMeaningfulChange || !isReady {
            persistDiary(result.newDiaryEntries)
            commit(silently: true)
        }

        drainIntentQueue()
        isReady = true
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            activate()
            refreshLiveActivity()
        case .background, .inactive:
            commit(silently: true)
        @unknown default:
            break
        }
    }

    // MARK: - Interactions

    func feed(_ itemID: String) {
        run { try $0.feed(itemID: itemID, pet: &$1, now: $2) }
    }

    /// Named `stroke` rather than `pet` because `pet` is the model here.
    func stroke() {
        run { try $0.petting(pet: &$1, now: $2) }
    }

    func play(toyID: String? = nil) {
        run { try $0.play(toyID: toyID, pet: &$1, now: $2) }
    }

    func clean() {
        run { try $0.clean(pet: &$1, now: $2) }
    }

    func rest() {
        run { try $0.rest(pet: &$1, now: $2) }
    }

    func explore() {
        run { try $0.startExploration(pet: &$1, now: $2) }
    }

    func wake() {
        run { try $0.wake(pet: &$1, now: $2) }
    }

    func cancelActivity() {
        run { try $0.cancelActivity(pet: &$1, now: $2) }
    }

    func equip(accessoryID: String?) {
        pet.equippedAccessoryID = accessoryID
        commit(silently: true)
        show(accessoryID == nil ? "取下了配饰" : "换上了配饰", failure: false)
    }

    func selectRoom(_ roomID: String) {
        guard let room = RoomCatalog.shared.room(roomID), pet.level >= room.requiredLevel else {
            show("等级不够，还用不了这个房间", failure: true)
            return
        }
        pet.roomID = roomID
        pet.backgroundID = RoomCatalog.shared.room(roomID)?.backgroundSprite ?? pet.backgroundID
        commit(silently: true)
        show("搬到了\(room.name)", failure: false)
    }

    func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pet.name = String(trimmed.prefix(12))
        commit(silently: true)
    }

    func dismissToast() { toast = nil }

    // MARK: - Core mutation path

    private func run(_ action: (inout InteractionService, inout PetState, Date) throws -> InteractionReceipt) {
        // Settle first so an interaction always operates on current numbers.
        settleQuietly()

        var working = pet
        var service = interactions
        do {
            let receipt = try action(&service, &working, clock.now)
            interactions = service
            pet = working

            if let event = receipt.triggeredEvent {
                persistDiary([.from(event, petID: pet.id)])
            }
            if let growth = receipt.growth, growth.didEvolve {
                persistDiary([
                    DiaryEntry.milestone(
                        petID: pet.id,
                        title: "进化 · \(growth.newStage.displayName)",
                        body: "Mochi 变成了\(growth.newStage.formName)。",
                        symbolName: "sparkles",
                        at: clock.now
                    )
                ])
            }

            commit(silently: false)
            show(receipt.message, failure: false)
            handleActivityChange(receipt)
        } catch let failure as InteractionFailure {
            show(failure.message, failure: true)
        } catch {
            show("操作失败", failure: true)
        }
    }

    private func settleQuietly() {
        var working = pet
        var rng = SeededGenerator(petID: pet.id, timestamp: pet.lastSimulatedAt)
        let result = simulator.settle(&working, now: clock.now, rng: &rng)
        pet = working
        if !result.newDiaryEntries.isEmpty {
            persistDiary(result.newDiaryEntries)
        }
    }

    private func handleActivityChange(_ receipt: InteractionReceipt) {
        if let activity = receipt.startedActivity {
            liveActivity.start(for: pet, activity: activity, now: clock.now)
        } else if pet.activeActivity == nil {
            liveActivity.endAll()
        }
    }

    private func refreshLiveActivity() {
        guard let activity = pet.activeActivity else {
            liveActivity.endAll()
            return
        }
        if activity.isFinished(at: clock.now) {
            liveActivity.endAll()
            return
        }
        Task { await liveActivity.update(for: pet, activity: activity, now: clock.now) }
    }

    // MARK: - Persistence

    private func commit(silently: Bool) {
        do {
            if let record {
                try record.apply(pet)
            } else {
                let created = try PetRecord(pet: pet)
                context.insert(created)
                record = created
            }
            try context.save()
        } catch {
            if !silently { show("保存失败：\(error.localizedDescription)", failure: true) }
        }

        let snapshot = PetSnapshot(pet)
        snapshots.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        if let activity = pet.activeActivity {
            Task { await liveActivity.update(for: pet, activity: activity, now: clock.now) }
        }
    }

    private func persistDiary(_ entries: [DiaryEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            if let record = try? DiaryRecord(entry: entry) {
                context.insert(record)
            }
        }
        try? context.save()
        diary = PetStore.loadDiary(in: context, petID: pet.id)
    }

    private func show(_ text: String, failure: Bool) {
        toast = Toast(text: text, isFailure: failure)
    }

    // MARK: - Intents

    /// Applies anything queued by Shortcuts or a widget tap.
    func drainIntentQueue() {
        let actions = IntentBridge.drain()
        guard !actions.isEmpty else { return }
        for action in actions {
            switch action {
            case .feed:
                if let food = ItemCatalog.shared.foods.first(where: { pet.count(of: $0.id) > 0 }) {
                    feed(food.id)
                }
            case .pet:     stroke()
            case .play:    play()
            case .explore: explore()
            case .wake:    wake()
            }
        }
    }

    // MARK: - Async helpers for views

    func requestNotificationPermission() async {
        _ = await notifications.requestAuthorization()
    }

    func scheduleGentleReminder() async {
        await notifications.scheduleCareReminder(for: pet)
    }

    // MARK: - Loading

    private static func loadOrCreatePet(in context: ModelContext, now: Date) -> (pet: PetState, record: PetRecord?) {
        let descriptor = FetchDescriptor<PetRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        if let existing = try? context.fetch(descriptor).first,
           let decoded = existing.decode() {
            return (decoded, existing)
        }

        // A record that exists but cannot be decoded is a corrupt save. Do not
        // resurrect ghost data — start clean and drop the broken row.
        if let stale = try? context.fetch(descriptor) {
            for record in stale { context.delete(record) }
            try? context.save()
        }

        let pet = PetState(name: "Mochi", createdAt: now)
        let record = try? PetRecord(pet: pet)
        if let record { context.insert(record) }
        try? context.save()
        return (pet, record)
    }

    private static func loadDiary(in context: ModelContext, petID: UUID, limit: Int = 300) -> [DiaryEntry] {
        var descriptor = FetchDescriptor<DiaryRecord>(
            predicate: #Predicate { $0.petID == petID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.compactMap { $0.decode() }
    }
}
