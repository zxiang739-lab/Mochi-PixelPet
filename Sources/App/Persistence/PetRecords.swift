import Foundation
import SwiftData

/// Persistence wrapper for the pet.
///
/// The authoritative `PetState` is stored as one encoded payload rather than
/// thirty‐odd columns. The reason is migration, not laziness: the domain model
/// will keep gaining fields, and one `Data` column with a `schemaVersion` inside
/// the JSON is far easier to migrate safely than a table that changes shape on
/// every release. The scalar columns that exist alongside it are only there for
/// queries the app actually performs (newest pet, diary by date).
@Model
final class PetRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var level: Int
    var stageRaw: String
    var updatedAt: Date
    var payload: Data

    init(pet: PetState, encoder: JSONEncoder = PetRecord.encoder) throws {
        self.id = pet.id
        self.name = pet.name
        self.level = pet.level
        self.stageRaw = pet.stage.rawValue
        self.updatedAt = pet.lastSimulatedAt
        self.payload = try encoder.encode(pet)
    }

    func apply(_ pet: PetState, encoder: JSONEncoder = PetRecord.encoder) throws {
        self.name = pet.name
        self.level = pet.level
        self.stageRaw = pet.stage.rawValue
        self.updatedAt = pet.lastSimulatedAt
        self.payload = try encoder.encode(pet)
    }

    func decode(decoder: JSONDecoder = PetRecord.decoder) -> PetState? {
        try? decoder.decode(PetState.self, from: payload)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@Model
final class DiaryRecord {
    @Attribute(.unique) var id: UUID
    var petID: UUID
    var createdAt: Date
    var categoryRaw: String
    var title: String
    var body: String
    var payload: Data

    init(entry: DiaryEntry, encoder: JSONEncoder = PetRecord.encoder) throws {
        self.id = entry.id
        self.petID = entry.petID
        self.createdAt = entry.createdAt
        self.categoryRaw = entry.category.rawValue
        self.title = entry.title
        self.body = entry.body
        self.payload = try encoder.encode(entry)
    }

    func decode(decoder: JSONDecoder = PetRecord.decoder) -> DiaryEntry? {
        try? decoder.decode(DiaryEntry.self, from: payload)
    }
}
