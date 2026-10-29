import SwiftUI
import WidgetKit

struct PetStatusWidget: Widget {
    let kind = "PetStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PetTimelineProvider()) { entry in
            PetWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            accent(for: entry.snapshot).opacity(0.30),
                            accent(for: entry.snapshot).opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .widgetURL(URL(string: "mochi://home"))
        }
        .configurationDisplayName("Mochi 状态")
        .description("看一眼它现在的心情，点一下就能进去。")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct PetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PetEntry

    var body: some View {
        switch family {
        case .systemSmall:         SmallPetWidget(snapshot: entry.snapshot)
        case .systemMedium:        MediumPetWidget(snapshot: entry.snapshot)
        case .accessoryCircular:   CircularPetWidget(snapshot: entry.snapshot)
        case .accessoryRectangular: RectangularPetWidget(snapshot: entry.snapshot)
        case .accessoryInline:     Text(inlineText(entry.snapshot))
        default:                   SmallPetWidget(snapshot: entry.snapshot)
        }
    }

    private func inlineText(_ snapshot: PetSnapshot) -> String {
        "\(snapshot.name) · Lv.\(snapshot.level) · \(snapshot.moodLabel)"
    }
}

// MARK: - Home screen

private struct SmallPetWidget: View {
    let snapshot: PetSnapshot

    var body: some View {
        VStack(spacing: 2) {
            Image(posterName(for: snapshot))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(maxHeight: 62)
                .accessibilityHidden(true)

            Text(snapshot.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("Lv.\(snapshot.level)")
                    .font(.caption2.monospacedDigit())
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(snapshot.moodLabel)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediumPetWidget: View {
    let snapshot: PetSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(posterName(for: snapshot))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 74, height: 74)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(snapshot.name)
                        .font(.subheadline.weight(.semibold))
                    Text("Lv.\(snapshot.level)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let kind = snapshot.activeActivityKind {
                        Label(kind.displayName, systemImage: kind.symbolName)
                            .font(.caption2)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(snapshot.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                meter("心情", snapshot.mood)
                meter("饱食", snapshot.satiety)
                meter("精力", snapshot.energy)

                Text("陪伴 \(snapshot.companionDays) 天")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func meter(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.10))
                    Capsule()
                        .fill(accent(for: snapshot))
                        .frame(width: max(3, proxy.size.width * min(max(value / 100, 0), 1)))
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Lock screen

private struct CircularPetWidget: View {
    let snapshot: PetSnapshot

    var body: some View {
        Gauge(value: min(max(snapshot.mood / 100, 0), 1)) {
            Image(systemName: "heart.fill")
        } currentValueLabel: {
            Text("\(Int(snapshot.mood))")
                .font(.caption2.monospacedDigit())
        }
        .gaugeStyle(.accessoryCircular)
    }
}

private struct RectangularPetWidget: View {
    let snapshot: PetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(snapshot.name)
                    .font(.caption.weight(.semibold))
                Text("Lv.\(snapshot.level)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("心情 \(Int(snapshot.mood)) · 陪伴 \(snapshot.companionDays) 天")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
