import ActivityKit
import Foundation

/// Wraps ActivityKit so the rest of the app never has to think about whether
/// Live Activities are authorised, supported, or already running.
@MainActor
final class LiveActivityManager {
    private var current: Activity<MochiActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(for pet: PetState, activity: ActiveActivity, now: Date) {
        guard isSupported else { return }
        endAll()

        let attributes = MochiActivityAttributes(
            petName: pet.name,
            kindRawValue: activity.kind.rawValue,
            stageRawValue: pet.stage.rawValue
        )
        let state = MochiActivityAttributes.ContentState(
            mood: pet.stats.mood.value,
            progress: activity.progress(at: now),
            remaining: activity.remaining(at: now),
            behavior: activity.kind.behavior.rawValue,
            caption: caption(for: activity.kind)
        )

        do {
            current = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: activity.endsAt),
                pushType: nil
            )
        } catch {
            // Live Activities can be disabled by the user or unsupported on the
            // device; this is not an error worth surfacing.
            current = nil
        }
    }

    func update(for pet: PetState, activity: ActiveActivity, now: Date) async {
        guard let current else { return }
        let state = MochiActivityAttributes.ContentState(
            mood: pet.stats.mood.value,
            progress: activity.progress(at: now),
            remaining: activity.remaining(at: now),
            behavior: activity.kind.behavior.rawValue,
            caption: caption(for: activity.kind)
        )
        await current.update(.init(state: state, staleDate: activity.endsAt))
    }

    func endAll() {
        let activities = Activity<MochiActivityAttributes>.activities
        guard !activities.isEmpty else {
            current = nil
            return
        }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        current = nil
    }

    private func caption(for kind: ActiveActivity.Kind) -> String {
        switch kind {
        case .nap:     "睡着了一会儿"
        case .explore: "出门探索中"
        case .play:    "玩得正起劲"
        }
    }
}
