import SwiftUI

struct SettingsView: View {
    @Environment(PetStore.self) private var store
    @State private var cloud = CloudSyncManager()
    @State private var notificationStatus = "未询问"
    @State private var showsRename = false
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("宠物") {
                    Button {
                        draftName = store.pet.name
                        showsRename = true
                    } label: {
                        LabeledContent("名字", value: store.pet.name)
                    }

                    LabeledContent("形态", value: store.pet.stage.displayName)
                    LabeledContent("等级", value: "Lv.\(store.pet.level)")
                    LabeledContent("陪伴", value: "\(store.pet.companionDays) 天")
                }

                Section {
                    Toggle("iCloud 同步", isOn: Binding(
                        get: { cloud.isEnabled },
                        set: { newValue in
                            cloud.isEnabled = newValue
                            cloud.refreshAvailability()
                            if newValue {
                                Task { await cloud.push(store.pet) }
                            }
                        }
                    ))
                    LabeledContent("状态", value: cloud.status.text)
                } header: {
                    Text("同步")
                } footer: {
                    Text("同步是可选的。关掉它，宠物照样按本地时间生活。")
                }

                Section {
                    Button("开启提醒") {
                        Task {
                            _ = await store.requestNotificationPermission()
                            await store.scheduleGentleReminder()
                            notificationStatus = await NotificationScheduler().authorizationStatusDescription()
                        }
                    }
                    LabeledContent("通知权限", value: notificationStatus)
                } header: {
                    Text("提醒")
                } footer: {
                    Text("只在它真的需要你时才提醒。不会用来维持后台运行。")
                }

                Section {
                    LabeledContent("小组件数据", value: store.isWidgetDataShared ? "已共享" : "未共享")
                    LabeledContent("上次结算",
                                   value: store.pet.lastSimulatedAt.formatted(.dateTime.month().day().hour().minute()))
                    if let result = store.lastSettlement {
                        LabeledContent("离线时长", value: durationText(result.elapsed))
                        LabeledContent("结算事件", value: "\(result.events.count) 条")
                        if result.wasCapped {
                            LabeledContent("结算上限", value: "已截断至 72 小时")
                        }
                    }
                } header: {
                    Text("运行状态")
                } footer: {
                    if !store.isWidgetDataShared {
                        Text("当前构建没有 App Group 权限（无签名构建），小组件会显示占位数据。用你自己的开发者证书签名后即可正常共享。")
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.appVersion)
                    LabeledContent("构建", value: Bundle.main.buildNumber)
                    LabeledContent("美术", value: "程序化生成 · 原创")
                }
            }
            .navigationTitle("设置")
            .task {
                notificationStatus = await NotificationScheduler().authorizationStatusDescription()
                cloud.refreshAvailability()
            }
            .alert("给它改个名字", isPresented: $showsRename) {
                TextField("名字", text: $draftName)
                Button("取消", role: .cancel) {}
                Button("保存") { store.rename(to: draftName) }
            }
        }
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
