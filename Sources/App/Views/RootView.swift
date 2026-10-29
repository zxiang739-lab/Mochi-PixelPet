import SwiftUI

struct RootView: View {
    let store: PetStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: MochiTab = .home

    enum MochiTab: Hashable {
        case home, bag, diary, profile, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("小屋", systemImage: "house.fill", value: MochiTab.home) {
                HomeView()
            }
            Tab("背包", systemImage: "bag.fill", value: MochiTab.bag) {
                BagView()
            }
            Tab("日记", systemImage: "book.closed.fill", value: MochiTab.diary) {
                DiaryView()
            }
            Tab("成长", systemImage: "chart.line.uptrend.xyaxis", value: MochiTab.profile) {
                ProfileView()
            }
            Tab("设置", systemImage: "gearshape.fill", value: MochiTab.settings) {
                SettingsView()
            }
        }
        .environment(store)
        .overlay(alignment: .top) { toastLayer }
        .task { store.activate() }
        .onChange(of: scenePhase) { _, phase in
            store.scenePhaseChanged(to: phase)
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = store.toast {
            HStack(spacing: 8) {
                Image(systemName: toast.isFailure ? "exclamationmark.triangle.fill" : "sparkles")
                    .foregroundStyle(toast.isFailure ? .orange : .accentColor)
                Text(toast.text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.panel(tint: toast.isFailure ? .orange : .accentColor), in: .capsule)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { store.dismissToast() }
            .task(id: toast.id) {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.snappy) { store.dismissToast() }
            }
            .animation(.snappy, value: toast.id)
        }
    }
}
