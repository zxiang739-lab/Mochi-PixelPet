import AppIntents
import Foundation

/// Shortcuts actions.
///
/// Each intent is intentionally small and side-effect-light: it reads the shared
/// snapshot for its dialog, and enqueues the real mutation through `IntentBridge`.
/// The app applies it on next activation through `InteractionService`, so there
/// is still exactly one writer of pet state in the whole system.
struct FeedMochiIntent: AppIntent {
    static let title: LocalizedStringResource = "喂 Mochi"
    static let description = IntentDescription("给 Mochi 喂一份背包里的食物。")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentBridge.enqueue(.feed)
        let name = SnapshotStore().load()?.name ?? "Mochi"
        return .result(dialog: "把食物放在 \(name) 面前了。")
    }
}

struct PetMochiIntent: AppIntent {
    static let title: LocalizedStringResource = "摸摸 Mochi"
    static let description = IntentDescription("摸摸它，亲密度会慢慢涨。")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentBridge.enqueue(.pet)
        let snapshot = SnapshotStore().load()
        let mood = snapshot.map { "心情 \(Int($0.mood))" } ?? "还在等你回来"
        return .result(dialog: "摸了摸 \(snapshot?.name ?? "Mochi")，\(mood)。")
    }
}

struct PlayWithMochiIntent: AppIntent {
    static let title: LocalizedStringResource = "陪 Mochi 玩"
    static let description = IntentDescription("用背包里的玩具陪它玩一会儿。")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentBridge.enqueue(.play)
        return .result(dialog: "它跑过来了。")
    }
}

struct MochiStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "查看 Mochi 状态"
    static let description = IntentDescription("读出当前等级、心情和需求。")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SnapshotStore().load() else {
            return .result(dialog: "还没找到 Mochi 的数据，先打开一次 App 吧。")
        }
        let line = "\(snapshot.name) · Lv.\(snapshot.level) · \(snapshot.moodLabel) · \(snapshot.hint)"
        return .result(dialog: "\(line)")
    }
}

struct MochiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PetMochiIntent(),
            phrases: [
                "摸摸 \(.applicationName)",
                "陪 \(.applicationName) 玩"
            ],
            shortTitle: "摸摸它",
            systemImageName: "hand.tap.fill"
        )
        AppShortcut(
            intent: MochiStatusIntent(),
            phrases: [
                "看看 \(.applicationName) 怎么样",
                "\(.applicationName) 状态"
            ],
            shortTitle: "查看状态",
            systemImageName: "heart.text.square.fill"
        )
        AppShortcut(
            intent: FeedMochiIntent(),
            phrases: ["喂 \(.applicationName)"],
            shortTitle: "喂食",
            systemImageName: "fork.knife"
        )
    }
}
