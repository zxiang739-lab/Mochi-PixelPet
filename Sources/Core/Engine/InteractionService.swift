import Foundation

/// A player-visible failure with a message that can be shown verbatim.
struct InteractionFailure: Error, Sendable, Equatable {
    let message: String
    /// Seconds until the same action is allowed again, when that is the reason.
    let retryAfter: TimeInterval?

    init(_ message: String, retryAfter: TimeInterval? = nil) {
        self.message = message
        self.retryAfter = retryAfter
    }
}

/// What actually happened, in numbers the UI can display honestly.
struct InteractionReceipt: Sendable {
    var message: String
    var appliedDeltas = StatDeltas()
    var growth: GrowthOutcome?
    var behavior: BehaviorState = .idle
    var triggeredEvent: ResolvedEvent?
    var consumedItems: [ItemReward] = []
    var experience: Int = 0
    var startedActivity: ActiveActivity?
}

/// The only place that mutates a pet in response to a tap.
///
/// Views never touch `PetState` fields directly — they call into this service,
/// which validates, mutates through the bounded-stat API, applies XP through the
/// growth engine and reports back a receipt. One writer, one order of operations,
/// no chance of two screens disagreeing about what a button does.
struct InteractionService: Sendable {
    let growth: GrowthEngine
    let events: EventEngine
    let tuning: SimulationTuning

    init(
        growth: GrowthEngine = GrowthEngine(),
        events: EventEngine = EventEngine(),
        tuning: SimulationTuning = .standard
    ) {
        self.growth = growth
        self.events = events
        self.tuning = tuning
    }

    // MARK: - Feeding

    mutating func feed(
        itemID: String,
        pet: inout PetState,
        now: Date
    ) throws -> InteractionReceipt {
        try requireAwake(pet)
        try requireCooldown("feed", pet: pet, now: now)

        guard let item = ItemCatalog.shared.item(itemID) else {
            throw InteractionFailure("没有这种食物")
        }
        guard item.category == .food else {
            throw InteractionFailure("\(item.name) 不是食物")
        }
        guard pet.level >= item.requiredLevel else {
            throw InteractionFailure("等级 \(item.requiredLevel) 才能解锁 \(item.name)")
        }
        guard pet.count(of: itemID) > 0 else {
            throw InteractionFailure("\(item.name) 已经吃完了")
        }
        guard pet.stats.satiety.value < 99 else {
            throw InteractionFailure("已经吃饱了，再吃会不舒服")
        }

        pet.consumeItem(itemID)
        let applied = pet.stats.apply(item.effects)
        pet.counters.feeds += 1
        pet.recordInteraction("feed", at: now)
        pet.behavior = .make(.eat, at: now)

        let xp = 6 + item.rarity.rawValue * 4
        let outcome = growth.apply(experience: xp, to: &pet)

        var receipt = InteractionReceipt(
            message: "\(pet.name) 吃掉了 \(item.name)",
            appliedDeltas: applied
        )
        receipt.growth = outcome
        receipt.behavior = .eat
        receipt.consumedItems = [ItemReward(itemID)]
        receipt.experience = xp
        return receipt
    }

    // MARK: - Petting

    mutating func petting(pet: inout PetState, now: Date) throws -> InteractionReceipt {
        try requireCooldown("pet", pet: pet, now: now)

        // Petting a sleeping pet wakes it — that is a choice with a cost, not
        // an error, so it succeeds but with a mood penalty.
        var extra = StatDeltas()
        if pet.behavior.state.isSleeping {
            pet.behavior = .make(.wake, at: now)
            extra.mood = -3
        }

        // Bond gain diminishes as it approaches the cap, so a new player and a
        // veteran see comparable progress per tap.
        let bondGain = max(0.25, 1.4 * (1 - pet.stats.bond.normalized))
        var deltas = StatDeltas(mood: 2.5, bond: bondGain)
        deltas = deltas + extra

        let applied = pet.stats.apply(deltas)
        pet.counters.pets += 1
        pet.recordInteraction("pet", at: now)
        if !pet.behavior.state.isSleeping {
            pet.behavior = .make(.pet, at: now)
        }

        let xp = 3
        let outcome = growth.apply(experience: xp, to: &pet)

        var receipt = InteractionReceipt(
            message: extra.mood < 0 ? "你把它弄醒了，它有点不情愿" : "\(pet.name) 眯起了眼睛",
            appliedDeltas: applied
        )
        receipt.growth = outcome
        receipt.behavior = pet.behavior.state
        receipt.experience = xp
        return receipt
    }

    // MARK: - Playing

    mutating func play(
        toyID: String?,
        pet: inout PetState,
        now: Date
    ) throws -> InteractionReceipt {
        try requireAwake(pet)
        try requireCooldown("play", pet: pet, now: now)

        let toy = toyID
            .flatMap { ItemCatalog.shared.item($0) }
            ?? pet.inventory.keys
                .compactMap { ItemCatalog.shared.item($0) }
                .first { $0.category == .toy }

        guard let toy else {
            throw InteractionFailure("背包里还没有玩具")
        }
        guard pet.stats.energy.value >= 15 else {
            throw InteractionFailure("它太累了，先让它休息一下")
        }

        var deltas = StatDeltas(mood: 9, energy: -7, cleanliness: -4)
        deltas = deltas + toy.effects
        let applied = pet.stats.apply(deltas)

        pet.counters.plays += 1
        pet.recordInteraction("play", at: now)
        pet.behavior = .make(.play, at: now)

        let xp = 12
        let outcome = growth.apply(experience: xp, to: &pet)

        var receipt = InteractionReceipt(
            message: "你们玩了 \(toy.name)",
            appliedDeltas: applied
        )
        receipt.growth = outcome
        receipt.behavior = .play
        receipt.experience = xp
        return receipt
    }

    // MARK: - Cleaning

    mutating func clean(pet: inout PetState, now: Date) throws -> InteractionReceipt {
        try requireCooldown("clean", pet: pet, now: now)

        let soap = ItemCatalog.shared.item("care.soap")
        let brush = ItemCatalog.shared.item("care.brush")

        let tool: ItemDefinition
        var consumed: [ItemReward] = []
        if pet.count(of: "care.soap") > 0, let soap {
            tool = soap
            pet.consumeItem("care.soap")
            consumed = [ItemReward("care.soap")]
        } else if let brush {
            tool = brush
        } else {
            throw InteractionFailure("没有可以用的清洁工具")
        }

        guard pet.stats.cleanliness.value < 99 else {
            throw InteractionFailure("已经很干净了")
        }

        let applied = pet.stats.apply(tool.effects)
        pet.recordInteraction("clean", at: now)
        pet.counters.cleans += 1
        pet.behavior = .make(.happy, at: now)

        let xp = 5
        let outcome = growth.apply(experience: xp, to: &pet)

        var receipt = InteractionReceipt(
            message: "用 \(tool.name) 清理干净了",
            appliedDeltas: applied
        )
        receipt.growth = outcome
        receipt.behavior = .happy
        receipt.consumedItems = consumed
        receipt.experience = xp
        return receipt
    }

    // MARK: - Resting

    mutating func rest(pet: inout PetState, now: Date) throws -> InteractionReceipt {
        try requireCooldown("rest", pet: pet, now: now)

        guard pet.activeActivity == nil else {
            throw InteractionFailure("它正在\(pet.activeActivity?.kind.displayName ?? "忙")中")
        }
        guard !pet.behavior.state.isSleeping else {
            throw InteractionFailure("它已经睡着了")
        }

        let activity = ActiveActivity(
            id: UUID(),
            kind: .nap,
            startedAt: now,
            endsAt: now.addingTimeInterval(ActiveActivity.Kind.nap.duration)
        )
        pet.activeActivity = activity
        pet.behavior = BehaviorInstance(state: .sleep, startedAt: now, endsAt: nil)
        pet.counters.rests += 1
        pet.recordInteraction("rest", at: now)

        var receipt = InteractionReceipt(message: "\(pet.name) 睡着了", behavior: .sleep)
        receipt.startedActivity = activity
        receipt.experience = 0
        return receipt
    }

    // MARK: - Exploration

    mutating func startExploration(pet: inout PetState, now: Date) throws -> InteractionReceipt {
        try requireCooldown("explore", pet: pet, now: now)

        guard pet.activeActivity == nil else {
            throw InteractionFailure("它正在\(pet.activeActivity?.kind.displayName ?? "忙")中")
        }
        guard !pet.behavior.state.isSleeping else {
            throw InteractionFailure("睡着了，等它醒吧")
        }
        guard pet.stats.energy.value >= 20 else {
            throw InteractionFailure("精力不够，探索会很勉强")
        }

        let activity = ActiveActivity(
            id: UUID(),
            kind: .explore,
            startedAt: now,
            endsAt: now.addingTimeInterval(ActiveActivity.Kind.explore.duration)
        )
        pet.activeActivity = activity
        pet.behavior = BehaviorInstance(state: .explore, startedAt: now, endsAt: activity.endsAt)
        pet.recordInteraction("explore", at: now)

        var receipt = InteractionReceipt(message: "\(pet.name) 出去了，说不好什么时候回来", behavior: .explore)
        receipt.startedActivity = activity
        return receipt
    }

    /// Player-initiated cancellation. Returns the pet to idle without rewards.
    mutating func cancelActivity(pet: inout PetState, now: Date) throws -> InteractionReceipt {
        guard pet.activeActivity != nil else {
            throw InteractionFailure("它没有在进行中的活动")
        }
        pet.activeActivity = nil
        pet.behavior = .make(.idle, at: now)
        return InteractionReceipt(message: "叫回来了", behavior: .idle)
    }

    /// Wakes a sleeping pet without any other effect.
    mutating func wake(pet: inout PetState, now: Date) throws -> InteractionReceipt {
        guard pet.behavior.state.isSleeping || pet.activeActivity?.kind == .nap else {
            throw InteractionFailure("它醒着")
        }
        pet.activeActivity = nil
        pet.behavior = .make(.wake, at: now)
        return InteractionReceipt(message: "\(pet.name) 醒了", behavior: .wake)
    }

    // MARK: - Validation

    private func requireAwake(_ pet: PetState) throws {
        if pet.behavior.state.isSleeping {
            throw InteractionFailure("它睡着了，先摸摸它叫醒")
        }
    }

    private func requireCooldown(_ action: String, pet: PetState, now: Date) throws {
        let remaining = pet.remainingCooldown(for: action, at: now)
        guard remaining > 0 else { return }
        throw InteractionFailure(
            "太快了，等一下",
            retryAfter: remaining
        )
    }
}
