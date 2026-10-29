import Foundation

/// Four growth stages. Stage is derived from level rather than stored
/// independently, so the two can never disagree.
enum GrowthStage: String, CaseIterable, Codable, Sendable, Comparable {
    case hatchling
    case sproutling
    case bloomtail
    case aurora

    var displayName: String {
        switch self {
        case .hatchling:  "露珠幼体"
        case .sproutling: "萌芽期"
        case .bloomtail:  "花尾期"
        case .aurora:     "极光期"
        }
    }

    var formName: String {
        switch self {
        case .hatchling:  "Dewdrop"
        case .sproutling: "Sproutling"
        case .bloomtail:  "Bloomtail"
        case .aurora:     "Auroramochi"
        }
    }

    var minimumLevel: Int {
        switch self {
        case .hatchling:  1
        case .sproutling: 10
        case .bloomtail:  25
        case .aurora:     50
        }
    }

    /// Prefix used by the generated sprite sheet names, e.g. `pet_dewdrop_idle`.
    var spritePrefix: String {
        switch self {
        case .hatchling:  "pet_dewdrop"
        case .sproutling: "pet_sprout"
        case .bloomtail:  "pet_bloom"
        case .aurora:     "pet_aurora"
        }
    }

    var accentColorHex: String {
        switch self {
        case .hatchling:  "7FD8C4"
        case .sproutling: "9ED77A"
        case .bloomtail:  "E79BC8"
        case .aurora:     "8FA8F0"
        }
    }

    /// Body scale applied in the scene so later forms read as visibly larger.
    var renderScale: Double {
        switch self {
        case .hatchling:  1.0
        case .sproutling: 1.12
        case .bloomtail:  1.24
        case .aurora:     1.38
        }
    }

    static func == (lhs: GrowthStage, rhs: GrowthStage) -> Bool { lhs.rawValue == rhs.rawValue }
    static func < (lhs: GrowthStage, rhs: GrowthStage) -> Bool {
        lhs.minimumLevel < rhs.minimumLevel
    }

    static func forLevel(_ level: Int) -> GrowthStage {
        GrowthStage.allCases.last { level >= $0.minimumLevel } ?? .hatchling
    }

    var next: GrowthStage? {
        let all = GrowthStage.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}
