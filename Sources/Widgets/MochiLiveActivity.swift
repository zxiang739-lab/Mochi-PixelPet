import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity for timed activities (napping, exploring, playing).
///
/// The activity never drives the simulation — it is a read-only window onto a
/// countdown that the app already computed. If it expires, is dismissed, or is
/// never started, the pet's state is still resolved correctly from timestamps on
/// the next launch.
struct MochiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MochiActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(posterName(for: context.attributes))
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.petName)
                            .font(.caption.weight(.semibold))
                        Text(context.state.caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(remainingText(context.state.remaining))
                            .font(.caption.monospacedDigit().weight(.semibold))
                        Text("心情 \(Int(context.state.mood))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(Color(hex: context.attributes.stage.accentColorHex))
                }
            } compactLeading: {
                Image(systemName: ActivityKindSymbol.symbol(for: context.attributes.kindRawValue))
                    .foregroundStyle(Color(hex: context.attributes.stage.accentColorHex))
            } compactTrailing: {
                Text(remainingText(context.state.remaining))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: ActivityKindSymbol.symbol(for: context.attributes.kindRawValue))
                    .foregroundStyle(Color(hex: context.attributes.stage.accentColorHex))
            }
            .keylineTint(Color(hex: context.attributes.stage.accentColorHex))
        }
    }

    private func remainingText(_ remaining: TimeInterval) -> String {
        let minutes = Int(max(0, remaining) / 60)
        if minutes <= 0 { return "即将结束" }
        return "\(minutes) 分钟"
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<MochiActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(posterName(for: context.attributes))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(context.attributes.petName)
                        .font(.subheadline.weight(.semibold))
                    Text(context.state.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: context.state.progress)
                    .tint(Color(hex: context.attributes.stage.accentColorHex))
                Text("心情 \(Int(context.state.mood))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: ActivityKindSymbol.symbol(for: context.attributes.kindRawValue))
                .font(.title3)
                .foregroundStyle(Color(hex: context.attributes.stage.accentColorHex))
        }
        .padding(14)
    }
}

enum ActivityKindSymbol {
    static func symbol(for rawValue: String) -> String {
        ActiveActivity.Kind(rawValue: rawValue)?.symbolName ?? "sparkles"
    }
}

/// Poster name helper for the Live Activity, which only has the raw stage string.
func posterName(for attributes: MochiActivityAttributes) -> String {
    attributes.stage.spritePrefix.replacingOccurrences(of: "pet_", with: "poster_")
}
