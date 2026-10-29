import SwiftUI
import WidgetKit

struct PetEntry: TimelineEntry {
    let date: Date
    let snapshot: PetSnapshot
}

/// Reads only the shared snapshot. The extension has no SwiftData store and no
/// access to the app's memory, which is exactly the constraint the product spec
/// asks for — the widget must work when the app is not running.
struct PetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: Date(), snapshot: .placeholder(now: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        let snapshot = SnapshotStore().load() ?? .placeholder(now: Date())
        completion(PetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotStore().load() ?? .placeholder(now: now)

        var entries = [PetEntry(date: now, snapshot: snapshot)]
        // One extra entry at the moment the current animation or activity ends,
        // so the widget can flip to a resting pose without a full reload.
        if let next = snapshot.nextChangeAt, next > now, next < now.addingTimeInterval(3600) {
            entries.append(PetEntry(date: next, snapshot: snapshot))
        }

        // 20 minutes is well inside the system's discretionary budget. Refreshes
        // are a request, not a promise — the widget is designed to tolerate
        // stale-by-minutes data.
        let refresh = now.addingTimeInterval(20 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

func posterName(for snapshot: PetSnapshot) -> String {
    snapshot.stage.spritePrefix.replacingOccurrences(of: "pet_", with: "poster_")
}

func accent(for snapshot: PetSnapshot) -> Color {
    Color(hex: snapshot.stage.accentColorHex)
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255,
            opacity: 1
        )
    }
}
