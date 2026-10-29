import Foundation

enum ItemCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case food
    case toy
    case care
    case accessory
    case furniture
    case background
    case collectible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food:        "食物"
        case .toy:         "玩具"
        case .care:        "护理"
        case .accessory:   "配饰"
        case .furniture:   "家具"
        case .background:  "背景"
        case .collectible: "收藏品"
        }
    }

    var symbolName: String {
        switch self {
        case .food:        "carrot.fill"
        case .toy:         "tennisball.fill"
        case .care:        "bubbles.and.sparkles.fill"
        case .accessory:   "party.popper.fill"
        case .furniture:   "sofa.fill"
        case .background:  "photo.fill"
        case .collectible: "seal.fill"
        }
    }
}

enum ItemRarity: Int, Codable, Sendable, Comparable {
    case common = 0
    case uncommon = 1
    case rare = 2
    case legendary = 3

    var displayName: String {
        switch self {
        case .common:    "普通"
        case .uncommon:  "少见"
        case .rare:      "稀有"
        case .legendary: "传说"
        }
    }

    static func < (lhs: ItemRarity, rhs: ItemRarity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How an item is allowed to enter the player's world.
enum AcquisitionSource: String, Codable, Sendable {
    case starter
    case exploration
    case event
    case shop
    case levelUp

    var displayName: String {
        switch self {
        case .starter:     "初始"
        case .exploration: "探索获得"
        case .event:       "事件奖励"
        case .shop:        "商店"
        case .levelUp:     "成长解锁"
        }
    }
}

struct ItemDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let category: ItemCategory
    let detail: String
    /// Asset catalogue name for the item's pixel icon, when one is generated.
    let spriteName: String?
    let rarity: ItemRarity
    let source: AcquisitionSource
    /// Whether using it removes one unit from the bag.
    let isConsumable: Bool
    /// Minimum pet level required to equip or use it.
    let requiredLevel: Int
    /// Stat change applied on use.
    let effects: StatDeltas
    /// Shop price in shells; `nil` when the item cannot be bought.
    let price: Int?

    init(
        id: String,
        name: String,
        category: ItemCategory,
        detail: String,
        spriteName: String? = nil,
        rarity: ItemRarity = .common,
        source: AcquisitionSource = .shop,
        isConsumable: Bool = false,
        requiredLevel: Int = 1,
        effects: StatDeltas = StatDeltas(),
        price: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.detail = detail
        self.spriteName = spriteName ?? id
        self.rarity = rarity
        self.source = source
        self.isConsumable = isConsumable
        self.requiredLevel = requiredLevel
        self.effects = effects
        self.price = price
    }
}

struct RoomDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    /// Background sprite drawn behind the pet in the SpriteKit scene.
    let backgroundSprite: String
    let requiredLevel: Int
    let defaultFurniture: [String]
}

// MARK: - Catalogue

/// Item data. Kept as plain data (not SwiftData) so both the app and the widget
/// extension can read it without opening a store.
struct ItemCatalog: Sendable {
    static let shared = ItemCatalog()

    let items: [ItemDefinition]
    private let index: [String: ItemDefinition]

    init(items: [ItemDefinition] = ItemCatalog.builtIn) {
        self.items = items
        self.index = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    func item(_ id: String) -> ItemDefinition? { index[id] }

    func items(in category: ItemCategory) -> [ItemDefinition] {
        items.filter { $0.category == category }
            .sorted { ($0.rarity.rawValue, $0.requiredLevel) > ($1.rarity.rawValue, $1.requiredLevel) }
    }

    var foods: [ItemDefinition] { items(in: .food) }

    static let builtIn: [ItemDefinition] = [
        // ---- 食物 ----
        ItemDefinition(
            id: "food.berry", name: "晨露浆果", category: .food,
            detail: "带一点酸味的野果，Mochi 总是先闻再咬。",
            source: .starter, isConsumable: true,
            effects: StatDeltas(satiety: 18, mood: 2, cleanliness: -2, bond: 1),
            price: 4
        ),
        ItemDefinition(
            id: "food.honeycake", name: "蜜渍米糕", category: .food,
            detail: "压在叶子里的甜点，吃一口会眯起眼睛。",
            source: .shop, isConsumable: true, requiredLevel: 3,
            effects: StatDeltas(satiety: 30, mood: 7, cleanliness: -6, bond: 2),
            price: 12
        ),
        ItemDefinition(
            id: "food.starfruit", name: "星形果", category: .food,
            detail: "切开是六角形的，据说是从天上掉下来的种子长成。",
            rarity: .rare, source: .exploration, isConsumable: true, requiredLevel: 5,
            effects: StatDeltas(satiety: 22, mood: 12, energy: 8, bond: 3),
            price: 28
        ),
        ItemDefinition(
            id: "food.moonmilk", name: "月乳", category: .food,
            detail: "睡前喝一小杯，醒来毛会变得很顺。",
            source: .shop, isConsumable: true, requiredLevel: 2,
            effects: StatDeltas(satiety: 12, energy: 22, mood: 4),
            price: 15
        ),
        ItemDefinition(
            id: "food.crispbug", name: "脆壳虫", category: .food,
            detail: "蛋白质很高。Mochi 假装不喜欢，其实每次都吃完了。",
            source: .exploration, isConsumable: true,
            effects: StatDeltas(satiety: 26, mood: 3, cleanliness: -4),
            price: 9
        ),

        // ---- 玩具 ----
        ItemDefinition(
            id: "toy.leafball", name: "卷叶球", category: .toy,
            detail: "滚起来会沙沙响，是最经得起折腾的玩具。",
            source: .starter,
            effects: StatDeltas(mood: 10, energy: -6, bond: 2),
            price: 10
        ),
        ItemDefinition(
            id: "toy.glowring", name: "微光环", category: .toy,
            detail: "抛起来会悬停半秒。它盯着看的样子很好笑。",
            rarity: .uncommon, source: .shop, requiredLevel: 4,
            effects: StatDeltas(mood: 14, energy: -8, bond: 3),
            price: 26
        ),
        ItemDefinition(
            id: "toy.windchime", name: "风铃草束", category: .toy,
            detail: "挂在窗边，风一过就发出很轻的声音。",
            rarity: .rare, source: .event, requiredLevel: 6,
            effects: StatDeltas(mood: 18, energy: -4, bond: 5),
            price: 40
        ),

        // ---- 护理 ----
        ItemDefinition(
            id: "care.soap", name: "皂泡", category: .care,
            detail: "揉出来的泡比它自己还大。",
            source: .starter, isConsumable: true,
            effects: StatDeltas(cleanliness: 45, mood: 4, bond: 1),
            price: 6
        ),
        ItemDefinition(
            id: "care.brush", name: "软毛刷", category: .care,
            detail: "顺着毛的方向刷，会发出满足的呼噜声。",
            source: .shop,
            effects: StatDeltas(cleanliness: 30, mood: 8, bond: 4),
            price: 18
        ),

        // ---- 配饰 ----
        ItemDefinition(
            id: "acc.mosshat", name: "苔帽", category: .accessory,
            detail: "一顶潮湿的小帽子，边缘会长出新芽。",
            rarity: .uncommon, source: .event, requiredLevel: 7,
            effects: StatDeltas(mood: 5), price: 45
        ),
        ItemDefinition(
            id: "acc.starclip", name: "星屑发夹", category: .accessory,
            detail: "别在耳朵旁边，晚上会有一点微光。",
            rarity: .rare, source: .exploration, requiredLevel: 12,
            effects: StatDeltas(mood: 8, bond: 2), price: 80
        ),
        ItemDefinition(
            id: "acc.auroraribbon", name: "极光缎带", category: .accessory,
            detail: "颜色会随角度变化，没有两次看起来是一样的。",
            rarity: .legendary, source: .levelUp, requiredLevel: 25,
            effects: StatDeltas(mood: 15, bond: 6), price: nil
        ),

        // ---- 家具 ----
        ItemDefinition(
            id: "furniture.lamp", name: "萤灯", category: .furniture,
            detail: "三只萤火虫轮流发光，永远不同步。",
            source: .shop, requiredLevel: 2, price: 30
        ),
        ItemDefinition(
            id: "furniture.cushion", name: "苔垫", category: .furniture,
            detail: "睡上去会陷下去一点点。",
            source: .starter, price: 16
        ),
        ItemDefinition(
            id: "furniture.aquarium", name: "小水族箱", category: .furniture,
            detail: "里面只有两只透明的虾，但看很久也不腻。",
            rarity: .uncommon, source: .exploration, requiredLevel: 6, price: 65
        ),
        ItemDefinition(
            id: "furniture.swing", name: "藤蔓秋千", category: .furniture,
            detail: "从天花板垂下来，晃起来有节奏。",
            rarity: .rare, source: .event, requiredLevel: 10, price: 90
        ),

        // ---- 背景 ----
        ItemDefinition(
            id: "bg.meadow", name: "苔原小屋", category: .background,
            detail: "默认的房间。光线总是下午四点。",
            source: .starter
        ),
        ItemDefinition(
            id: "bg.cavern", name: "荧光洞窟", category: .background,
            detail: "顶上垂着会呼吸的光苔。",
            rarity: .uncommon, source: .exploration, requiredLevel: 8, price: 120
        ),
        ItemDefinition(
            id: "bg.sky", name: "云上平台", category: .background,
            detail: "地板是云，踩下去会有回声。",
            rarity: .rare, source: .event, requiredLevel: 18, price: 200
        ),

        // ---- 收藏品 ----
        ItemDefinition(
            id: "col.feather", name: "极光羽", category: .collectible,
            detail: "不知道是什么鸟留下的。摸上去是凉的。",
            rarity: .rare, source: .exploration, requiredLevel: 3
        ),
        ItemDefinition(
            id: "col.geode", name: "星核晶簇", category: .collectible,
            detail: "敲开的话里面应该有东西，但没人舍得敲。",
            rarity: .legendary, source: .exploration, requiredLevel: 15
        ),
        ItemDefinition(
            id: "col.shell", name: "螺旋贝", category: .collectible,
            detail: "贴着耳朵能听见很远的潮声。",
            rarity: .uncommon, source: .exploration, requiredLevel: 5
        )
    ]
}

struct RoomCatalog: Sendable {
    static let shared = RoomCatalog()

    let rooms: [RoomDefinition]

    init(rooms: [RoomDefinition] = RoomCatalog.builtIn) {
        self.rooms = rooms
    }

    func room(_ id: String) -> RoomDefinition? { rooms.first { $0.id == id } }

    static let builtIn: [RoomDefinition] = [
        RoomDefinition(
            id: "room.meadow", name: "苔原小屋",
            detail: "牠出生的地方。地板是压实的三叶草。",
            backgroundSprite: "bg_meadow", requiredLevel: 1,
            defaultFurniture: ["furniture.cushion"]
        ),
        RoomDefinition(
            id: "room.cavern", name: "荧光洞窟",
            detail: "安静、湿润，适合睡觉。",
            backgroundSprite: "bg_cavern", requiredLevel: 8,
            defaultFurniture: ["furniture.lamp"]
        ),
        RoomDefinition(
            id: "room.sky", name: "云上平台",
            detail: "风很大，但牠似乎不介意。",
            backgroundSprite: "bg_sky", requiredLevel: 18,
            defaultFurniture: ["furniture.swing"]
        )
    ]
}
