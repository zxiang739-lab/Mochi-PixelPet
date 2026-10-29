# Mochi — Pixel Pet

一只原生 iOS 幻想宠物。完全本地规则驱动，不依赖任何 AI 服务与第三方素材，断网可玩。

用 SwiftUI + SpriteKit 构建，界面全面采用 **iOS 26 Liquid Glass**（`glassEffect` / `GlassEffectContainer` / `.glass` 按钮样式），并接入 WidgetKit、ActivityKit 灵动岛、App Intents 与 SwiftData。

---

## 快速开始

```bash
git clone https://github.com/zxiang739-lab/Mochi-PixelPet.git
cd Mochi-PixelPet

# 工程由 XcodeGen 从 project.yml 生成（仓库里已附带生成结果）
brew install xcodegen
xcodegen generate

open Mochi.xcodeproj
```

在 Xcode 中选择任意 iOS 26 模拟器即可运行。**最低部署版本 iOS 26.0** —— 液态玻璃是硬性视觉要求，而它只存在于 iOS 26。

### 重新生成像素素材

所有精灵图由脚本程序化绘制，没有任何外部美术资源：

```bash
python3 Tools/generate_sprites.py
```

输出 4 个成长形态 × 14 种状态的多帧精灵表、3 张房间背景、4 张宣传帧与 App 图标，直接写入 `Resources/Assets.xcassets`。替换美术时只需换掉这个脚本的绘制逻辑，或按 `Docs/ART_GUIDE.md` 的规范整体替换 imageset。

---

## 运行测试

```bash
xcodebuild test -project Mochi.xcodeproj -scheme Mochi \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

- `MochiTests` — 领域层单元测试（离线结算、事件引擎、性格漂移、成长曲线、交互校验、快照存储）
- `MochiUITests` — 关键流程 UI 测试

CI（`.github/workflows/ci.yml`）在 GitHub 托管的 `macos-26` 机器上执行同样的流程，并把构建产物、测试结果和模拟器截图作为 artifact 上传。

---

## 架构

```
Sources/
├── Core/                 纯 Swift，无 UI 依赖，App 与 Widget 共享
│   ├── Models/           PetState / PetStats / Personality / BehaviorState / …
│   ├── Engine/           OfflineSimulator · EventEngine · PersonalityEngine
│   │                     GrowthEngine · InteractionService · GameClock
│   ├── Content/          ItemCatalog · EventCatalog · RoomCatalog（纯数据）
│   └── Shared/           SnapshotStore · MochiActivityAttributes · IntentBridge
├── App/                  SwiftUI 界面 + SpriteKit 场景 + SwiftData 持久化
└── Widgets/              WidgetKit 组件 + Live Activity
Tests/                    单元测试与 UI 测试
Tools/                    素材生成脚本
```

三条设计约束贯穿全局：

1. **单一写入者**。视图从不直接修改 `PetState`，所有变更经 `InteractionService` 与 `OfflineSimulator`。快照、SwiftData、WidgetKit 刷新由 `PetStore` 一处提交。
2. **时间戳是唯一真相**。宠物不依赖后台循环运行；每次进入前台用「上次结算时间 → 现在」重建它的生活。后台任务不参与状态推进，因此不存在「App 没被唤醒所以宠物卡住」的问题。
3. **纯值类型领域层**。所有状态都是 `struct`，结算要么整体提交要么完全不生效，测试可以用固定时钟与固定随机种子完整复现。

---

## 离线模拟的几个关键取舍

| 风险 | 处理方式 |
|---|---|
| 同一段时间被重复结算 | `lastSimulatedAt` 在结算开始时即推进到 `now`，崩溃时宁可少给也不重复给 |
| 修改系统时间刷收益 | 负时间差直接归零并标记 `clockWentBackwards`，不发放任何奖励 |
| 离开很久后爆出大量事件 | 单次结算窗口上限 72 小时，分块数上限 256，单次事件数上限 4 |
| 反复开关 App 触发结算 | 90 秒内的进入视为同一次，不产生衰减与事件 |
| 重装后凭空恢复数据 | 记录存在但解码失败时视为损坏存档并丢弃，不猜测恢复 |

这些行为全部有对应测试，见 `Tests/MochiCoreTests/OfflineSettlementTests.swift`。

---

## 已知限制（诚实地列出）

本项目在 **Windows 环境**下开发，没有 macOS / Xcode / 模拟器，因此：

- **编译与测试在 GitHub Actions 的 macOS runner 上完成**，不是本机。构建日志与产物见 Actions 页面。
- **未在真机验证**。CI 只做无签名模拟器构建，`.app` 可直接装入模拟器，但不能装进 iPhone。
- **要在真机运行**，需要用你自己的 Apple Developer 账号签名，并在 Xcode 中为 App 与 Widget Extension 都开启 App Groups（`group.com.zxiang739.mochi.shared`）。
- **无签名构建下列表组件拿不到 App Group 容器**，`SnapshotStore` 会退化到 App 私有目录，小组件因此显示占位数据。设置页会如实显示「未共享」，不假装正常。
- **CloudKit 同步需要真实的 iCloud 容器 entitlement**。代码是完整实现（私有数据库、冲突按时间戳取新），但未配置容器时会在运行时降级为「不可用」，不影响 App 使用。
- **语言模式为 Swift 5**（`SWIFT_STRICT_CONCURRENCY: minimal`）。领域层本身是纯值类型、天然 Sendable，但 SpriteKit 的触摸回调与 SwiftUI 场景装配在 Swift 6 严格并发下需要额外的隔离标注。选择 Swift 5 模式是为了在没有本地编译环境的情况下保证构建确定性，迁移路径已标注在代码注释中。

---

## 素材与许可

- 所有像素美术由 `Tools/generate_sprites.py` 程序化生成，原创，无第三方素材、字体或音效。
- 不使用 Emoji 或 SF Symbols 代替宠物形象；SF Symbols 仅用于按钮与物品类别图标。

## 数据模型版本

`PetState.schemaVersion` 与 `PetSnapshot.schemaVersion` 各自独立。快照版本不匹配时小组件拒绝读取并显示占位，而非猜测半份数据。
