import Foundation

/// The complete local event set.
///
/// Every entry is data: a weight, a cooldown, declarative requirements and a
/// diary paragraph. The engine never special-cases an id, which is what makes
/// the whole system testable — you can assert "with these stats, only these
/// three events are eligible" without touching a database or a clock.
struct EventCatalog: Sendable {
    static let shared = EventCatalog()

    let events: [PetEventDefinition]

    init(events: [PetEventDefinition] = EventCatalog.builtIn) {
        self.events = events
    }

    func event(_ id: String) -> PetEventDefinition? { events.first { $0.id == id } }

    func events(in category: EventCategory) -> [PetEventDefinition] {
        events.filter { $0.category == category }
    }

    static let builtIn: [PetEventDefinition] = [

        // ---------------------------------------------------------- 探索发现
        PetEventDefinition(
            id: "ev.explore.mossgrove",
            category: .exploration,
            title: "苔丛深处",
            diaryText: "你钻进屋子后面那片苔丛，出来的时候背甲上挂了三根草籽。你好像觉得这是战利品。",
            requirements: EventRequirements(minLevel: 1, minExplorations: 0),
            weight: 1.2, cooldown: 40 * 60,
            effects: StatDeltas(mood: 6, energy: -4, cleanliness: -8),
            rewards: [ItemReward("col.shell")],
            experience: 8,
            animation: .explore
        ),
        PetEventDefinition(
            id: "ev.explore.glowriver",
            category: .exploration,
            title: "发光溪流",
            diaryText: "你沿着水声走到一条溪边。水面浮着会发光的孢子，你伸爪碰了一下，它们散开又慢慢聚回来。",
            requirements: EventRequirements(minLevel: 4, minEnergy: 25),
            weight: 1.0, cooldown: 90 * 60,
            effects: StatDeltas(mood: 9, energy: -6, cleanliness: 10, bond: 1),
            rewards: [ItemReward("food.starfruit")],
            experience: 12,
            animation: .curious
        ),
        PetEventDefinition(
            id: "ev.explore.oldstone",
            category: .exploration,
            title: "旧石阶",
            diaryText: "你发现了一段被草盖住的石阶，往上走了七级就停住了。你在那里坐了很久，什么也没做。",
            requirements: EventRequirements(minLevel: 6, minMood: 40),
            weight: 0.8, cooldown: 3 * 3600,
            effects: StatDeltas(mood: 5, energy: -8, bond: 2),
            experience: 14,
            animation: .explore
        ),
        PetEventDefinition(
            id: "ev.explore.starfall",
            category: .exploration,
            title: "陨星碎屑",
            diaryText: "地上有一小块还在发热的石头。你绕着它转了三圈，最后把整个身体趴了上去。",
            requirements: EventRequirements(minLevel: 8, minExplorations: 5, minTraits: [.curiosity: 0.55]),
            weight: 0.5, cooldown: 6 * 3600,
            effects: StatDeltas(mood: 14, energy: -10, bond: 3),
            rewards: [ItemReward("col.feather")],
            experience: 26,
            animation: .surprise
        ),
        PetEventDefinition(
            id: "ev.explore.fogpath",
            category: .exploration,
            title: "雾里的小径",
            diaryText: "雾很厚，你走了大概二十分钟，回来时路线完全不一样。你不肯说发生了什么。",
            requirements: EventRequirements(minLevel: 12, minExplorations: 15, minTraits: [.independence: 0.6]),
            weight: 0.4, cooldown: 12 * 3600,
            effects: StatDeltas(mood: 11, energy: -14, cleanliness: -12, bond: 4),
            rewards: [ItemReward("acc.starclip")],
            experience: 40,
            animation: .explore
        ),

        // -------------------------------------------------------------- 收藏
        PetEventDefinition(
            id: "ev.collect.geode",
            category: .collectible,
            title: "星核晶簇",
            diaryText: "你在岩缝里掏出一块沉甸甸的东西，敲了敲，里面有光在动。你没舍得再敲第二下。",
            requirements: EventRequirements(minLevel: 15, minExplorations: 10),
            weight: 0.25, cooldown: 24 * 3600,
            effects: StatDeltas(mood: 18, bond: 5),
            rewards: [ItemReward("col.geode")],
            experience: 60,
            animation: .celebrate
        ),
        PetEventDefinition(
            id: "ev.collect.shell",
            category: .collectible,
            title: "螺旋贝",
            diaryText: "你捡到一枚螺旋贝，把它贴在耳朵上听了很久。后来你把它藏在了垫子下面。",
            requirements: EventRequirements(minLevel: 3),
            weight: 0.6, cooldown: 5 * 3600,
            effects: StatDeltas(mood: 7, bond: 2),
            rewards: [ItemReward("col.shell")],
            experience: 10,
            animation: .curious
        ),

        // ------------------------------------------------------------ 新玩具
        PetEventDefinition(
            id: "ev.toy.glowring",
            category: .toyDiscovery,
            title: "捡到一个会浮的环",
            diaryText: "不知道是谁掉的。你把它抛起来，它悬在半空停了一秒才落下，你被自己吓了一跳。",
            requirements: EventRequirements(minLevel: 4, minMood: 50),
            weight: 0.5, cooldown: 10 * 3600,
            effects: StatDeltas(mood: 12, energy: -6),
            rewards: [ItemReward("toy.glowring")],
            experience: 18,
            animation: .surprise
        ),
        PetEventDefinition(
            id: "ev.toy.windchime",
            category: .toyDiscovery,
            title: "风铃草束",
            diaryText: "一束风铃草卡在窗框上，风一过就响。你听了整个下午，尾巴一直在打拍子。",
            requirements: EventRequirements(minLevel: 7, minBond: 30),
            weight: 0.35, cooldown: 20 * 3600,
            effects: StatDeltas(mood: 16, bond: 4),
            rewards: [ItemReward("toy.windchime")],
            experience: 30,
            animation: .happy
        ),

        // -------------------------------------------------------- 特别互动
        PetEventDefinition(
            id: "ev.special.stare",
            category: .specialInteraction,
            title: "对视",
            diaryText: "你们对视了很久，久到你先眨眼。然后你假装什么都没发生，去舔爪子了。",
            requirements: EventRequirements(minBond: 25, requiresAwake: true),
            weight: 0.9, cooldown: 2 * 3600,
            effects: StatDeltas(mood: 8, bond: 4),
            experience: 8,
            animation: .curious
        ),
        PetEventDefinition(
            id: "ev.special.shoulderNap",
            category: .specialInteraction,
            title: "靠着睡着",
            diaryText: "你本来只是想靠一下，结果睡着了，还打了一点点呼噜。",
            requirements: EventRequirements(minBond: 35, minEnergy: 0, maxEnergy: 35, requiresAwake: true),
            weight: 0.7, cooldown: 3 * 3600,
            effects: StatDeltas(mood: 12, energy: 10, bond: 6),
            experience: 14,
            animation: .sleep
        ),
        PetEventDefinition(
            id: "ev.special.gift",
            category: .specialInteraction,
            title: "叼来的东西",
            diaryText: "你叼了片叶子放到我脚边，然后退后两步看着我。我等了很久才明白那是礼物。",
            requirements: EventRequirements(minLevel: 5, minBond: 45),
            weight: 0.6, cooldown: 8 * 3600,
            effects: StatDeltas(mood: 14, bond: 8),
            rewards: [ItemReward("col.feather")],
            experience: 22,
            animation: .happy
        ),
        PetEventDefinition(
            id: "ev.special.dance",
            category: .specialInteraction,
            title: "原地转圈",
            diaryText: "你突然开始原地转圈，转了八九圈，然后直直撞到垫子上，躺着不动了。",
            requirements: EventRequirements(minEnergy: 50, minMood: 75),
            weight: 0.5, cooldown: 4 * 3600,
            effects: StatDeltas(mood: 10, energy: -12),
            experience: 12,
            animation: .celebrate
        ),

        // -------------------------------------------------------------- 节日
        PetEventDefinition(
            id: "ev.festival.newyear",
            category: .festival,
            title: "新年",
            diaryText: "窗外有很远的响声和光。你躲在窗帘后面看了很久，最后把头搁在我手边。",
            requirements: EventRequirements(minLevel: 1, allowedMonths: [1]),
            weight: 2.5, cooldown: 36 * 3600,
            effects: StatDeltas(mood: 20, energy: -5, bond: 6),
            rewards: [ItemReward("food.honeycake", 2)],
            experience: 30,
            animation: .celebrate
        ),
        PetEventDefinition(
            id: "ev.festival.midsummer",
            category: .festival,
            title: "仲夏",
            diaryText: "这一天长得出奇。你在光里睡了一整个下午，醒来时影子已经换了个方向。",
            requirements: EventRequirements(minLevel: 3, allowedMonths: [6, 7]),
            weight: 2.0, cooldown: 36 * 3600,
            effects: StatDeltas(mood: 16, energy: 12, cleanliness: -6),
            experience: 24,
            animation: .happy
        ),
        PetEventDefinition(
            id: "ev.festival.midautumn",
            category: .festival,
            title: "中秋",
            diaryText: "月亮很圆。你坐在窗台上看了很久，我切了一小块东西给你，你吃得很慢。",
            requirements: EventRequirements(minLevel: 2, allowedMonths: [9, 10]),
            weight: 2.0, cooldown: 36 * 3600,
            effects: StatDeltas(satiety: 15, mood: 18, bond: 5),
            rewards: [ItemReward("food.starfruit")],
            experience: 26,
            animation: .celebrate
        ),

        // -------------------------------------------------------------- 成长
        PetEventDefinition(
            id: "ev.growth.firstBloom",
            category: .growth,
            title: "第一次开花",
            diaryText: "尾巴末端裂开了一小簇芽。你好像自己也发现了，绕着尾巴转了很久。",
            requirements: EventRequirements(minLevel: 10, stages: [.sproutling]),
            weight: 3.0, cooldown: 7 * 24 * 3600,
            effects: StatDeltas(mood: 20, bond: 8),
            experience: 50,
            animation: .celebrate,
            isHidden: false
        ),
        PetEventDefinition(
            id: "ev.growth.auroraWhisper",
            category: .growth,
            title: "极光的低语",
            diaryText: "你身上的颜色开始流动了。安静的时候最明显，像有人在里面点了灯。",
            requirements: EventRequirements(minLevel: 50, stages: [.aurora]),
            weight: 3.0, cooldown: 7 * 24 * 3600,
            effects: StatDeltas(mood: 25, bond: 10),
            rewards: [ItemReward("acc.auroraribbon")],
            experience: 80,
            animation: .celebrate
        ),

        // ---------------------------------------------------------- 隐藏事件
        PetEventDefinition(
            id: "ev.hidden.midnightVisitor",
            category: .hidden,
            title: "深夜有人来过",
            diaryText: "凌晨三点，你忽然醒了，对着空无一物的门口看了很久。然后你换了个姿势继续睡。",
            requirements: EventRequirements(minLevel: 6, minBond: 20, requiresSleeping: true, minimumOffline: 3 * 3600, allowedHours: [0, 1, 2, 3, 4]),
            weight: 0.3, cooldown: 24 * 3600,
            effects: StatDeltas(mood: -4, bond: 3),
            experience: 20,
            animation: .surprise,
            isHidden: true
        ),
        PetEventDefinition(
            id: "ev.hidden.longAbsence",
            category: .hidden,
            title: "你回来的时候",
            diaryText: "你离开了很久。我一直在同一个位置，只是把身体收紧了一点。",
            requirements: EventRequirements(minLevel: 1, minBond: 10, minimumOffline: 24 * 3600),
            weight: 1.5, cooldown: 12 * 3600,
            effects: StatDeltas(mood: -8, bond: 2),
            experience: 10,
            animation: .sad,
            isHidden: true
        ),
        PetEventDefinition(
            id: "ev.hidden.patience",
            category: .hidden,
            title: "一直等着",
            diaryText: "你没有催。你在门口坐了一会儿，然后又坐了一会儿。",
            requirements: EventRequirements(minLevel: 10, minBond: 50, minTraits: [.independence: 0.6], minimumOffline: 8 * 3600),
            weight: 0.4, cooldown: 24 * 3600,
            effects: StatDeltas(mood: 6, bond: 6),
            rewards: [ItemReward("furniture.swing")],
            experience: 45,
            animation: .idle,
            isHidden: true
        ),

        // ------------------------------------------------------------ 日常生活
        PetEventDefinition(
            id: "ev.daily.sunbeam",
            category: .dailyLife,
            title: "晒到太阳",
            diaryText: "一小块阳光移到地板上，你挪过去，正好把自己放进那块光里。",
            requirements: EventRequirements(minLevel: 1, allowedHours: [9, 10, 11, 12, 13, 14, 15]),
            weight: 1.4, cooldown: 3 * 3600,
            effects: StatDeltas(mood: 7, energy: 5),
            experience: 5,
            animation: .happy
        ),
        PetEventDefinition(
            id: "ev.daily.dustball",
            category: .dailyLife,
            title: "打滚",
            diaryText: "你在灰里滚了一圈，然后很满意地站起来，看着我。",
            requirements: EventRequirements(minLevel: 1, minEnergy: 40),
            weight: 1.1, cooldown: 2 * 3600,
            effects: StatDeltas(mood: 6, energy: -4, cleanliness: -14),
            experience: 4,
            animation: .play
        ),
        PetEventDefinition(
            id: "ev.daily.yawn",
            category: .dailyLife,
            title: "打哈欠",
            diaryText: "张大嘴打了很久的哈欠，打完眼睛都湿了。",
            requirements: EventRequirements(minLevel: 1, maxEnergy: 40),
            weight: 1.3, cooldown: 90 * 60,
            effects: StatDeltas(mood: 2, energy: -2),
            experience: 3,
            animation: .wake
        ),
        PetEventDefinition(
            id: "ev.daily.dreamMu",
            category: .dailyLife,
            title: "做梦",
            diaryText: "睡着的时候四条腿在轻轻划，像在跑。不知道梦见了什么。",
            requirements: EventRequirements(minLevel: 2, requiresSleeping: true, minimumOffline: 30 * 60),
            weight: 1.0, cooldown: 4 * 3600,
            effects: StatDeltas(mood: 5, energy: 6),
            experience: 6,
            animation: .sleep
        ),
        PetEventDefinition(
            id: "ev.daily.hungryStare",
            category: .dailyLife,
            title: "盯着空碗",
            diaryText: "碗是空的。你看了碗一会儿，又看了我一会儿。来回三次。",
            requirements: EventRequirements(minLevel: 1, maxSatiety: 20, requiresAwake: true),
            weight: 1.6, cooldown: 45 * 60,
            effects: StatDeltas(mood: -5),
            experience: 2,
            animation: .sad
        )
    ]
}
