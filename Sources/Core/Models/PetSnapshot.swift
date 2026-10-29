import Foundation

/// The only thing the widget extension is allowed to read.
///
/// Deliberately small, deliberately flat, deliberately redundant: a widget can
/// be asked for a timeline while the app is suspended or not installed at all,
/// so it must never depend on the app's object graph, its SwiftData store, or
/// its process being alive. Everything the widget needs is copied here on save.
struct PetSnapshot: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var petID: UUID
    var name: String
    var level: Int
    var stageRawValue: String
    var behaviorRawValue: String
    var mood: Double
    var energy: Double
    var satiety: Double
    var bond: Double
    var companionDays: Int
    var updatedAt: Date
    /// When the current one-shot animation or timed activity is expected to end.
    var nextChangeAt: Date?
    var activeActivityKind: String?
    var activeActivityEndsAt: Date?
    var dominantTraitRawValue: String?

    init(
        petID: UUID,
        name: String,
        level: Int,
        stage: GrowthStage,
        behavior: BehaviorState,
        mood: Double,
        energy: Double,
        satiety: Double,
        bond: Double,
        companionDays: Int,
        updatedAt: Date,
        nextChangeAt: Date? = nil,
        activeActivity: ActiveActivity? = nil,
        dominantTrait: PersonalityTrait? = nil
    ) {
        self.schemaVersion = PetSnapshot.currentSchemaVersion
        self.petID = petID
        self.name = name
        self.level = level
        self.stageRawValue = stage.rawValue
        self.behaviorRawValue = behavior.rawValue
        self.mood = mood
        self.energy = energy
        self.satiety = satiety
        self.bond = bond
        self.companionDays = companionDays
        self.updatedAt = updatedAt
        self.nextChangeAt = nextChangeAt
        self.activeActivityKind = activeActivity?.kind.rawValue
        self.activeActivityEndsAt = activeActivity?.endsAt
        self.dominantTraitRawValue = dominantTrait?.rawValue
    }

    var stage: GrowthStage { GrowthStage(rawValue: stageRawValue) ?? .hatchling }
    var behavior: BehaviorState { BehaviorState(rawValue: behaviorRawValue) ?? .idle }
    var dominantTrait: PersonalityTrait? {
        dominantTraitRawValue.flatMap(PersonalityTrait.init(rawValue:))
    }
    var activeActivityKind: ActiveActivity.Kind? {
        activeActivityKind.flatMap(ActiveActivity.Kind.init(rawValue:))
    }

    /// Sprite sheet name for the current form + behaviour, resolved without
    /// touching the asset catalogue (the extension cannot rely on bundle layout
    /// differences between app and extension).
    var spriteName: String { "\(stage.spritePrefix)_\(behavior.rawValue)" }

    var moodLabel: String {
        switch mood {
        case ..<20:  "很低落"
        case ..<40:  "有点闷"
        case ..<60:  "还行"
        case ..<80:  "不错"
        default:     "很开心"
        }
    }

    /// Short actionable line shown by the medium widget.
    var hint: String {
        if behavior == .sleep { return "正在睡觉" }
        if satiety < 25 { return "饿了" }
        if energy < 20 { return "累了" }
        if satiety < 45 { return "想吃点东西" }
        if mood < 40 { return "想被陪一会儿" }
        return "状态良好"
    }

    static func placeholder(now: Date) -> PetSnapshot {
        PetSnapshot(
            petID: UUID(),
            name: "Mochi",
            level: 1,
            stage: .hatchling,
            behavior: .idle,
            mood: 70,
            energy: 80,
            satiety: 70,
            bond: 10,
            companionDays: 1,
            updatedAt: now
        )
    }
}

extension PetSnapshot {
    init(_ pet: PetState) {
        self.init(
            petID: pet.id,
            name: pet.name,
            level: pet.level,
            stage: pet.stage,
            behavior: pet.behavior.state,
            mood: pet.stats.mood.value,
            energy: pet.stats.energy.value,
            satiety: pet.stats.satiety.value,
            bond: pet.stats.bond.value,
            companionDays: pet.companionDays,
            updatedAt: pet.lastSimulatedAt,
            nextChangeAt: pet.activeActivity?.endsAt ?? pet.behavior.endsAt,
            activeActivity: pet.activeActivity,
            dominantTrait: pet.personality.dominant
        )
    }
}
