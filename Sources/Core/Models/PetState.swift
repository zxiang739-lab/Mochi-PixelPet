import Foundation

/// Long-run behaviour counters. These — not the moment-to-moment stats — are
/// what the personality engine reads, so a pet's character reflects how it has
/// actually been treated over weeks rather than how it feels right now.
struct ActivityCounters: Codable, Hashable, Sendable {
    var interactions: Int = 0
    var feeds: Int = 0
    var pets: Int = 0
    var plays: Int = 0
    var explorations: Int = 0
    var cleans: Int = 0
    var rests: Int = 0
    var sleepsCompleted: Int = 0

    /// How many offline settlements have run, and how much wall-clock time they
    /// covered. The personality engine reads these to decide whether the pet
    /// has learned to be on its own.
    var offlineSettlements: Int = 0
    var totalOfflineSeconds: Double = 0

    var total: Int {
        interactions + feeds + pets + plays + explorations + cleans + rests
    }

    /// Mean time the player was away, in hours. Zero before the first return.
    var averageOfflineHours: Double {
        guard offlineSettlements > 0 else { return 0 }
        return (totalOfflineSeconds / Double(offlineSettlements)) / 3600
    }
}

/// A timed activity the pet is currently committed to. This is what the Live
/// Activity on the Dynamic Island renders, and what the offline simulator
/// resolves on the next launch.
struct ActiveActivity: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case nap
        case explore
        case play

        var displayName: String {
            switch self {
            case .nap:     "小睡"
            case .explore: "探索"
            case .play:    "玩耍"
            }
        }

        var symbolName: String {
            switch self {
            case .nap:     "moon.zzz.fill"
            case .explore: "map.fill"
            case .play:    "gamecontroller.fill"
            }
        }

        var duration: TimeInterval {
            switch self {
            case .nap:     20 * 60
            case .explore: 45 * 60
            case .play:    10 * 60
            }
        }

        var behavior: BehaviorState {
            switch self {
            case .nap:     .sleep
            case .explore: .explore
            case .play:    .play
            }
        }
    }

    var id: UUID
    var kind: Kind
    var startedAt: Date
    var endsAt: Date

    func isFinished(at now: Date) -> Bool { now >= endsAt }

    func progress(at now: Date) -> Double {
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(startedAt) / total, 0), 1)
    }

    func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }
}

/// The single source of truth for one pet.
///
/// This type is a plain value: the app persists it through SwiftData, the
/// widget reads a slimmer `PetSnapshot` derived from it, and the engines take
/// it `inout` and mutate it in place. Because it is a value type with fully
/// bounded sub-values, a settlement pass is atomic — either the whole result is
/// committed or nothing is.
struct PetState: Codable, Sendable, Identifiable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = PetState.currentSchemaVersion

    var id: UUID
    var name: String
    var createdAt: Date

    /// Timestamp of the last completed offline settlement. Always moved to
    /// "now" once a settlement finishes so the same window is never paid twice.
    var lastSimulatedAt: Date
    var lastInteractionAt: Date
    var lastVisitDay: Date?
    var streakDays: Int

    var level: Int
    var experience: Int

    var stats: PetStats
    var personality: Personality
    var behavior: BehaviorInstance

    var inventory: [String: Int]
    var unlockedItemIDs: Set<String>
    var equippedAccessoryID: String?
    var roomID: String
    var backgroundID: String

    var counters: ActivityCounters
    var eventCooldowns: [String: Date]
    var resolvedEventIDs: Set<String>
    var lastActionTimestamps: [String: Date]

    var activeActivity: ActiveActivity?
    var evolutionCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        stats: PetStats = PetStats(),
        personality: Personality = .neutral,
        level: Int = 1,
        experience: Int = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastSimulatedAt = createdAt
        self.lastInteractionAt = createdAt
        self.lastVisitDay = nil
        self.streakDays = 0
        self.level = level
        self.experience = experience
        self.stats = stats
        self.personality = personality
        self.behavior = BehaviorInstance.make(.idle, at: createdAt)
        self.inventory = PetState.starterInventory()
        self.unlockedItemIDs = ["room.meadow", "food.berry", "toy.leafball"]
        self.equippedAccessoryID = nil
        self.roomID = "room.meadow"
        self.backgroundID = "bg.meadow"
        self.counters = ActivityCounters()
        self.eventCooldowns = [:]
        self.resolvedEventIDs = []
        self.lastActionTimestamps = [:]
        self.activeActivity = nil
        self.evolutionCount = 0
    }

    // MARK: - Derived

    var stage: GrowthStage { GrowthStage.forLevel(level) }

    var companionDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: createdAt, to: lastInteractionAt).day ?? 1)
    }

    var isAsleep: Bool { behavior.state.isSleeping || activeActivity?.kind == .nap }

    /// Item count, tolerant of unknown ids so corrupted saves cannot crash.
    func count(of itemID: String) -> Int { inventory[itemID] ?? 0 }

    var equippedAccessory: ItemDefinition? {
        equippedAccessoryID.flatMap { ItemCatalog.shared.item($0) }
    }

    var room: RoomDefinition? { RoomCatalog.shared.room(roomID) }

    // MARK: - Mutation helpers (the only sanctioned ways to touch counters)

    mutating func recordInteraction(_ action: String, at now: Date) {
        counters.interactions += 1
        lastInteractionAt = now
        lastActionTimestamps[action] = now
    }

    mutating func grantItem(_ itemID: String, count amount: Int = 1) {
        guard amount > 0 else { return }
        inventory[itemID, default: 0] += amount
        unlockedItemIDs.insert(itemID)
    }

    @discardableResult
    mutating func consumeItem(_ itemID: String, count amount: Int = 1) -> Bool {
        let current = count(of: itemID)
        guard current >= amount else { return false }
        let remaining = current - amount
        if remaining == 0 {
            inventory.removeValue(forKey: itemID)
        } else {
            inventory[itemID] = remaining
        }
        return true
    }

    /// Minimum spacing between repeats of the same action, in seconds.
    /// Guards against double-taps and rapid-fire automated taps.
    static let actionCooldown: [String: TimeInterval] = [
        "feed": 6,
        "pet": 1.2,
        "play": 8,
        "clean": 15,
        "rest": 10,
        "explore": 60
    ]

    func remainingCooldown(for action: String, at now: Date) -> TimeInterval {
        guard let window = PetState.actionCooldown[action],
              let last = lastActionTimestamps[action] else { return 0 }
        let elapsed = now.timeIntervalSince(last)
        return max(0, window - elapsed)
    }

    static func starterInventory() -> [String: Int] {
        [
            "food.berry": 5,
            "food.honeycake": 2,
            "food.starfruit": 1,
            "toy.leafball": 1,
            "care.soap": 3
        ]
    }
}
