# 美术资源规范

Mochi 的全部像素素材由 `Tools/generate_sprites.py` 程序化生成。这份文档说明了资源结构，方便你在不碰代码的情况下整体替换美术。

## 网格与色板

| 项目 | 规格 |
|---|---|
| 单帧尺寸 | 32 × 32 px |
| 精灵表方向 | 横向条带，帧数由状态决定 |
| 轮廓 | 1px，由「剪影外扩」算法统一生成，不是逐部件描边 |
| 采样 | 全部资源在 SpriteKit 中标注 `filteringMode = .nearest`，禁止平滑缩放 |
| 显示尺寸 | 32 × 7 = 224 pt 基准，再乘以形态的 `renderScale`（1.0 / 1.12 / 1.24 / 1.38） |

每个成长形态一套独立色板，定义在脚本的 `PALETTES` 中：`body` / `shade` / `light` / `outline` / `accent` / `blush` 六个角色色。

## 资源命名

```
pet_<形态>_<状态>.png     e.g. pet_dewdrop_idle.png
poster_<形态>.png         e.g. poster_aurora.png（单帧宣传图，供小组件与灵动岛使用）
bg_<场景>.png             e.g. bg_cavern.png（96 × 64）
```

形态：`dewdrop` / `sprout` / `bloom` / `aurora`
场景：`meadow` / `cavern` / `sky`

## 状态与帧数（必须与 `BehaviorState.frameCount` 一致）

| 状态 | 帧数 | 单帧时长 | 循环 | 结束去向 |
|---|---|---|---|---|
| idle | 4 | 0.30s | 是 | — |
| walk | 6 | 0.16s | 是 | — |
| run | 6 | 0.10s | 是 | — |
| sleep | 3 | 0.55s | 是 | — |
| wake | 3 | 0.13s | 否 | idle |
| happy | 4 | 0.13s | 否 | idle |
| curious | 3 | 0.13s | 否 | idle |
| sad | 3 | 0.13s | 否 | idle |
| eat | 4 | 0.13s | 否 | happy |
| play | 4 | 0.13s | 否 | happy |
| pet | 4 | 0.13s | 否 | happy |
| surprise | 3 | 0.13s | 否 | curious |
| explore | 4 | 0.20s | 否 | idle |
| celebrate | 5 | 0.13s | 否 | happy |

## 替换方式

**方案 A — 改绘制逻辑（推荐）**

修改 `Tools/generate_sprites.py` 中的 `draw_creature()` 与 `frames_for()`，重跑脚本即可。所有比例、颜色、动作参数都在那里。

**方案 B — 整张替换**

1. 按上表准备好 32×32 的横向条带 PNG；
2. 覆盖 `Resources/Assets.xcassets/pet_<形态>_<状态>.imageset/` 内的同名文件；
3. 保持 `.imageset/Contents.json` 结构不变（单张 universal、单倍图）；
4. 如果改了帧数，必须同步修改 `Sources/Core/Models/BehaviorState.swift` 的 `frameCount`，否则切片会错位。

## 硬性要求

- 不使用 Emoji、SF Symbols 或位图字体替代宠物本体形象。
- 所有素材必须原创或具备可商用授权，不得直接取用任何商业游戏资源。
- 深色与浅色系统外观下都必须可辨识：宠物自身保持统一配色，不随系统明暗反转，由所在场景背景承担适配。
- 像素画不参与 Dynamic Type 缩放；文字信息由玻璃面板承载，保证辅助功能可读。
