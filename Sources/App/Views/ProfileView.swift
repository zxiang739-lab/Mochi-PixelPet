import SwiftUI

struct ProfileView: View {
    @Environment(PetStore.self) private var store

    private var pet: PetState { store.pet }
    private let growth = GrowthEngine()
    private let personalityEngine = PersonalityEngine()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    levelCard
                    stageRoadmap
                    personalityCard
                    achievementCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("成长")
        }
    }

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lv.\(pet.level)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(pet.stage.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pet.experience) / \(GrowthEngine.requirement(forLevel: pet.level) == Int.max ? pet.experience : GrowthEngine.requirement(forLevel: pet.level))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: growth.progressToNextLevel(for: pet))
                .tint(Color(hex: pet.stage.accentColorHex))

            Text("再获得 \(growth.experienceToNextLevel(for: pet)) 点经验即可升级")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassPanel(cornerRadius: 24)
    }

    private var stageRoadmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("形态")
                .font(.subheadline.weight(.semibold))

            ForEach(GrowthStage.allCases, id: \.self) { stage in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: stage.accentColorHex).opacity(pet.stage >= stage ? 1 : 0.25))
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(stage.displayName) · \(stage.formName)")
                            .font(.subheadline.weight(pet.stage == stage ? .semibold : .regular))
                        Text("Lv.\(stage.minimumLevel) 起")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if pet.stage == stage {
                        Text("当前")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .glassEffect(.panel(tint: .accentColor, interactive: false), in: .capsule)
                    } else if pet.stage > stage {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .glassPanel(cornerRadius: 24)
    }

    private var personalityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("性格")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(personalityEngine.summary(for: pet))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 190, alignment: .trailing)
            }

            ForEach(personalityEngine.insights(for: pet)) { insight in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: insight.trait.symbolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(insight.trait.displayName)
                            .font(.caption.weight(.medium))
                        Text(insight.headline)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", insight.value * 100))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.black.opacity(0.07))
                            Capsule()
                                .fill(Color(hex: pet.stage.accentColorHex))
                                .frame(width: max(8, proxy.size.width * insight.value))
                        }
                    }
                    .frame(height: 5)

                    Text(insight.evidence)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .glassPanel(cornerRadius: 24)
    }

    private var achievementCard: some View {
        let discovered = pet.resolvedEventIDs.count
        let total = EventCatalog.shared.events.count

        return VStack(alignment: .leading, spacing: 10) {
            Text("收集进度")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 16) {
                metric("事件", "\(discovered)/\(total)")
                metric("探索", "\(pet.counters.explorations)")
                metric("互动", "\(pet.counters.total)")
                metric("连续", "\(pet.streakDays) 天")
            }
        }
        .glassPanel(cornerRadius: 24)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
