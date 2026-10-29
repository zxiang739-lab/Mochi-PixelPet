import Foundation

/// One line in the pet's diary.
///
/// Stored as its own record so entries survive independently of the pet's live
/// state — a diary that loses history when a stat is reset is not a diary.
struct DiaryEntry: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let petID: UUID
    /// The catalogue event that produced this entry, when there was one.
    let eventID: String?
    let category: EventCategory
    let title: String
    let body: String
    let symbolName: String
    let createdAt: Date
    let grantedItemIDs: [String]
    let experience: Int
    let isMilestone: Bool

    init(
        id: UUID = UUID(),
        petID: UUID,
        eventID: String?,
        category: EventCategory,
        title: String,
        body: String,
        symbolName: String,
        createdAt: Date,
        grantedItemIDs: [String] = [],
        experience: Int = 0,
        isMilestone: Bool = false
    ) {
        self.id = id
        self.petID = petID
        self.eventID = eventID
        self.category = category
        self.title = title
        self.body = body
        self.symbolName = symbolName
        self.createdAt = createdAt
        self.grantedItemIDs = grantedItemIDs
        self.experience = experience
        self.isMilestone = isMilestone
    }

    static func from(_ event: ResolvedEvent, petID: UUID) -> DiaryEntry {
        DiaryEntry(
            petID: petID,
            eventID: event.definitionID,
            category: event.category,
            title: event.title,
            body: event.body,
            symbolName: event.symbolName,
            createdAt: event.timestamp,
            grantedItemIDs: event.grantedItems.map(\.itemID),
            experience: event.experience,
            isMilestone: event.isMilestone
        )
    }
}

/// System-written notes that are not random events: evolution, milestones,
/// first-time unlocks. Kept separate so the 日记 tab can filter them.
extension DiaryEntry {
    static func milestone(
        petID: UUID,
        title: String,
        body: String,
        symbolName: String,
        at date: Date,
        category: EventCategory = .growth
    ) -> DiaryEntry {
        DiaryEntry(
            petID: petID,
            eventID: nil,
            category: category,
            title: title,
            body: body,
            symbolName: symbolName,
            createdAt: date,
            isMilestone: true
        )
    }
}
