import SpriteKit
import SwiftUI

struct HomeView: View {
    @Environment(PetStore.self) private var store
    @State private var scene = PetScene(size: CGSize(width: 340, height: 340))
    @State private var showsFeedSheet = false
    @State private var pulse = false

    private var pet: PetState { store.pet }

    var body: some View {
        ZStack {
            roomBackground
            spriteLayer
            overlayControls
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showsFeedSheet) {
            FeedSheet()
                .environment(store)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Layers

    private var roomBackground: some View {
        Image(pet.room?.backgroundSprite ?? "bg_meadow")
            .resizable()
            .interpolation(.none)
            .scaledToFill()
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.06), .black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
    }

    private var spriteLayer: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .background(.clear)
            .onAppear {
                scene.onTap = { store.stroke() }
                scene.onLongPress = { store.play() }
                scene.update(stage: pet.stage, state: pet.behavior.state)
            }
            .onChange(of: pet.stage) { _, stage in
                scene.update(stage: stage, state: pet.behavior.state)
            }
            .onChange(of: pet.behavior.state) { _, state in
                scene.update(stage: pet.stage, state: state)
            }
            .onChange(of: pet.activeActivity?.kind) { _, kind in
                if kind != nil { scene.celebrateBurst() }
            }
            .accessibilityLabel("\(pet.name) 的像素场景，点击可抚摸")
    }

    private var overlayControls: some View {
        VStack(spacing: 12) {
            headerCard
            Spacer(minLength: 0)
            if let activity = pet.activeActivity {
                activityCard(activity)
            }
            statsCard
            actionDock
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 4)
    }

    // MARK: - Cards

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pet.name)
                        .font(.title3.weight(.semibold))
                    if let trait = pet.personality.dominant {
                        Text(trait.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .glassEffect(.panel(tint: .accentColor, interactive: false), in: .capsule)
                    }
                }
                Text("\(pet.stage.displayName) · \(pet.stage.formName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Lv.\(pet.level)")
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                Text("陪伴 \(pet.companionDays) 天")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .glassPanel(cornerRadius: 24, padding: 14)
    }

    private var statsCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                StatMeter(key: .satiety, value: pet.stats.satiety.value)
                StatMeter(key: .mood, value: pet.stats.mood.value)
            }
            HStack(spacing: 14) {
                StatMeter(key: .energy, value: pet.stats.energy.value)
                StatMeter(key: .cleanliness, value: pet.stats.cleanliness.value)
            }
            StatMeter(key: .bond, value: pet.stats.bond.value)
        }
        .glassPanel(cornerRadius: 26, padding: 14)
    }

    private func activityCard(_ activity: ActiveActivity) -> some View {
        let now = Date()
        let progress = activity.progress(at: now)
        let remaining = Int(activity.remaining(at: now) / 60)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: activity.kind.symbolName)
                    .foregroundStyle(.accent)
                Text("正在\(activity.kind.displayName)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(remaining > 0 ? "约 \(remaining) 分钟" : "快结束了")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("叫回") { store.cancelActivity() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
            }
            ProgressView(value: progress)
                .tint(.accentColor)
        }
        .glassPanel(tint: .accentColor, cornerRadius: 22, padding: 12)
    }

    private var actionDock: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                GlassActionButton(title: "抚摸", systemImage: "hand.tap.fill", tint: .pink) {
                    store.stroke()
                }
                GlassActionButton(
                    title: "喂食", systemImage: "fork.knife", tint: .orange,
                    isEnabled: canFeed
                ) { showsFeedSheet = true }
                GlassActionButton(
                    title: "玩耍", systemImage: "tennisball.fill", tint: .green,
                    isEnabled: canPlay
                ) { store.play() }
                GlassActionButton(
                    title: "清理", systemImage: "bubbles.and.sparkles.fill", tint: .cyan,
                    isEnabled: canClean
                ) { store.clean() }
                GlassActionButton(
                    title: pet.isAsleep ? "叫醒" : "睡觉",
                    systemImage: pet.isAsleep ? "sun.max.fill" : "moon.zzz.fill",
                    tint: .indigo,
                    isEnabled: pet.activeActivity == nil || pet.isAsleep
                ) { pet.isAsleep ? store.wake() : store.rest() }
                GlassActionButton(
                    title: "探索", systemImage: "map.fill", tint: .brown,
                    isEnabled: canExplore
                ) { store.explore() }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Availability

    private var canFeed: Bool {
        !pet.isAsleep && ItemCatalog.shared.foods.contains { pet.count(of: $0.id) > 0 }
    }
    private var canPlay: Bool {
        !pet.isAsleep && pet.stats.energy.value >= 15
    }
    private var canClean: Bool {
        pet.count(of: "care.soap") > 0
    }
    private var canExplore: Bool {
        !pet.isAsleep && pet.activeActivity == nil && pet.stats.energy.value >= 20
    }
}

// MARK: - Feeding

struct FeedSheet: View {
    @Environment(PetStore.self) private var store

    private var availableFoods: [ItemDefinition] {
        ItemCatalog.shared.foods.filter { store.pet.count(of: $0.id) > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if availableFoods.isEmpty {
                        ContentUnavailableView(
                            "背包里没有食物",
                            systemImage: "fork.knife",
                            description: Text("去探索看看，也许会带回来能吃的东西。")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(availableFoods) { item in
                            foodRow(item)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("喂点什么")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { store.dismissToast() }
                }
            }
        }
    }

    private func foodRow(_ item: ItemDefinition) -> some View {
        Button {
            store.feed(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.category.symbolName)
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        Text("×\(store.pet.count(of: item.id))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(item.effects.nonZeroItems.prefix(2)) { stat in
                        Text("\(stat.key.displayName) \(formatDelta(stat.value))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(stat.value >= 0 ? .green : .red)
                    }
                }
            }
            .padding(12)
            .glassPanel(cornerRadius: 20, padding: 0)
        }
        .buttonStyle(.plain)
        .disabled(store.pet.level < item.requiredLevel)
        .opacity(store.pet.level < item.requiredLevel ? 0.45 : 1)
    }
}
