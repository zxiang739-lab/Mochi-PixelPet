import SwiftData
import SwiftUI

@main
@MainActor
struct MochiApp: App {
    @State private var store: PetStore
    private let container: ModelContainer

    init() {
        let container = MochiApp.makeContainer()
        self.container = container

        let isUITest = ProcessInfo.processInfo.arguments.contains("-MochiUITestMode")
        let clock: GameClock = isUITest
            ? FixedClock(Date())
            : SystemClock()

        _store = State(
            initialValue: PetStore(
                context: container.mainContext,
                clock: clock,
                tuning: isUITest ? .fast : .standard
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .modelContainer(container)
        }
    }

    /// Prefers the on-disk store, falls back to memory for UI tests, and only
    /// gives up if neither can be constructed — which would mean the schema
    /// itself is broken, not the disk.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([PetRecord.self, DiaryRecord.self])
        let inMemory = ProcessInfo.processInfo.arguments.contains("-MochiUITestMode")

        let primary = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: schema, configurations: [primary]) {
            return container
        }

        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
            return container
        }

        preconditionFailure("SwiftData schema is invalid — cannot start Mochi")
    }
}
