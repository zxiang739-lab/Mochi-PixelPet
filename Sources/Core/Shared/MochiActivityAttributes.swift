import ActivityKit
import Foundation

/// Attributes for the Live Activity shown while Mochi is napping, exploring or
/// playing.
///
/// Lives in the shared sources so the app (which starts and ends activities) and
/// the widget extension (which renders them) agree on the schema without either
/// depending on the other's module.
struct MochiActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 0...100, drives the colour ramp.
        var mood: Double
        /// 0...1 completion of the underlying activity.
        var progress: Double
        /// Seconds remaining, computed by the app when it pushes an update.
        var remaining: TimeInterval
        /// `BehaviorState.rawValue` — kept as a string so a future state added in
        /// the app cannot crash an older activity.
        var behavior: String
        var caption: String
    }

    /// Fixed for the lifetime of the activity.
    var petName: String
    var kindRawValue: String
    var stageRawValue: String

    var kind: ActiveActivity.Kind {
        ActiveActivity.Kind(rawValue: kindRawValue) ?? .nap
    }

    var stage: GrowthStage {
        GrowthStage(rawValue: stageRawValue) ?? .hatchling
    }
}
