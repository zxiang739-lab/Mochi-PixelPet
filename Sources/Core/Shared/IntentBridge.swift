import Foundation

/// A tiny message bus between App Intents / widgets and the running app.
///
/// Shortcuts execute in the app's process when it is alive and in a lightweight
/// extension context when it is not. Rather than letting an intent try to mutate
/// SwiftData directly — which would mean a second writer and a second source of
/// truth — intents append a command here. The app drains the queue on activation
/// and applies everything through `InteractionService`, exactly like a tap.
enum IntentBridge {
    static let suiteName = SharedContainer.appGroupID
    static let pendingKey = "mochi.pendingIntentActions"

    enum Action: String, Codable, Sendable, CaseIterable {
        case feed
        case pet
        case play
        case explore
        case wake
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func enqueue(_ action: Action) {
        var queue = pending()
        queue.append(action.rawValue)
        defaults.set(queue, forKey: pendingKey)
    }

    static func pending() -> [String] {
        defaults.stringArray(forKey: pendingKey) ?? []
    }

    /// Returns the queued actions and clears them in one step.
    static func drain() -> [Action] {
        let raw = pending()
        defaults.removeObject(forKey: pendingKey)
        return raw.compactMap(Action.init(rawValue:))
    }

    static func clear() {
        defaults.removeObject(forKey: pendingKey)
    }
}
