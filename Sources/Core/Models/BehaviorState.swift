import Foundation

/// The full behaviour vocabulary of a Mochi.
///
/// Each case carries its own animation contract — how many frames the sprite
/// sheet row holds, how long one pass lasts, whether it loops, and which state
/// the creature falls into once the action completes. Keeping this in one place
/// means the SpriteKit scene, the Live Activity and the widget all agree on what
/// "eating" looks like and how long it takes.
enum BehaviorState: String, CaseIterable, Codable, Sendable {
    case idle
    case walk
    case run
    case sleep
    case wake
    case happy
    case curious
    case sad
    case eat
    case play
    case pet
    case surprise
    case explore
    case celebrate

    var displayName: String {
        switch self {
        case .idle:      "发呆"
        case .walk:      "散步"
        case .run:       "奔跑"
        case .sleep:     "睡着"
        case .wake:      "醒来"
        case .happy:     "开心"
        case .curious:   "好奇"
        case .sad:       "低落"
        case .eat:       "进食"
        case .play:      "玩耍"
        case .pet:       "被抚摸"
        case .surprise:  "惊讶"
        case .explore:   "探索"
        case .celebrate: "庆祝"
        }
    }

    /// One-shot duration. `nil` means "holds until something else happens".
    var duration: TimeInterval? {
        switch self {
        case .idle, .sleep: nil
        case .walk: 3.0
        case .run: 2.0
        case .wake: 1.2
        case .happy: 1.6
        case .curious: 2.0
        case .sad: 2.4
        case .eat: 2.8
        case .play: 3.2
        case .pet: 1.4
        case .surprise: 1.0
        case .explore: 6.0
        case .celebrate: 2.6
        }
    }

    var loops: Bool {
        switch self {
        case .idle, .sleep, .walk, .run: true
        default: false
        }
    }

    /// State entered when a one-shot animation finishes.
    var restingState: BehaviorState {
        switch self {
        case .wake, .surprise, .curious: .idle
        case .eat, .play, .pet, .celebrate: .happy
        case .happy, .sad, .walk, .run, .explore: .idle
        case .idle, .sleep: .idle
        }
    }

    /// Energy drained per second while this state is active.
    var energyDrainPerSecond: Double {
        switch self {
        case .sleep: -1.6          // negative = recovery
        case .idle: 0.02
        case .walk: 0.10
        case .run: 0.34
        case .play: 0.28
        case .explore: 0.20
        case .celebrate: 0.12
        case .eat: 0.0
        default: 0.0
        }
    }

    /// Rows per sprite sheet, used by the pixel atlas generator and the scene.
    var frameCount: Int {
        switch self {
        case .idle: 4
        case .walk: 6
        case .run: 6
        case .sleep: 3
        case .wake: 3
        case .happy: 4
        case .curious: 3
        case .sad: 3
        case .eat: 4
        case .play: 4
        case .pet: 4
        case .surprise: 3
        case .explore: 4
        case .celebrate: 5
        }
    }

    /// Seconds each animation frame is held. Sleep is deliberately slow so it
    /// reads as resting rather than a frozen frame.
    var secondsPerFrame: TimeInterval {
        switch self {
        case .sleep: 0.55
        case .idle: 0.30
        case .walk: 0.16
        case .run: 0.10
        case .explore: 0.20
        default: 0.13
        }
    }

    var isSleeping: Bool { self == .sleep }

    /// States the creature may be interrupted out of by user interaction.
    var isInterruptible: Bool {
        switch self {
        case .sleep, .explore: false
        default: true
        }
    }
}

/// A behaviour plus its timing envelope, persisted so that a relaunch can
/// resume mid-animation instead of snapping back to idle.
struct BehaviorInstance: Codable, Hashable, Sendable {
    var state: BehaviorState
    var startedAt: Date
    var endsAt: Date?

    init(state: BehaviorState, startedAt: Date, endsAt: Date? = nil) {
        self.state = state
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    static func make(_ state: BehaviorState, at now: Date) -> BehaviorInstance {
        BehaviorInstance(
            state: state,
            startedAt: now,
            endsAt: state.duration.map { now.addingTimeInterval($0) }
        )
    }

    func isFinished(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }
}
