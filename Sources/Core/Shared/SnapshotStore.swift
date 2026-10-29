import Foundation

/// Location strategy for the file the widget extension reads.
///
/// The App Group container is the only location both the app and the extension
/// can see, but it does not exist when the build is unsigned (CI simulator
/// builds) or when the profile lacks the group. Rather than crash or silently
/// write somewhere the widget can never read, the store exposes the weakness
/// explicitly through `isShared` so the settings screen can tell the truth.
enum SharedContainer {
    static let appGroupID = "group.com.zxiang739.mochi.shared"
    static let snapshotFileName = "pet-snapshot.json"

    static var groupDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// App-only directory used when no group container is available.
    static var fallbackDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MochiShared", isDirectory: true)
    }
}

/// Writes and reads the widget snapshot.
///
/// Concurrency model: exactly one writer (the app, on the main actor, serialised
/// by the store object) and any number of readers (widget extension). Safety
/// comes from atomic replace — a reader either sees the previous complete JSON
/// or the new complete JSON, never a half-written file. No file locking is
/// needed because there is no read-modify-write cycle.
struct SnapshotStore: Sendable {
    let directory: URL
    let isShared: Bool

    init(directory: URL? = SharedContainer.groupDirectory) {
        if let directory {
            self.directory = directory
            self.isShared = true
        } else {
            self.directory = SharedContainer.fallbackDirectory
            self.isShared = false
        }
    }

    static let shared = SnapshotStore()

    var fileURL: URL {
        directory.appendingPathComponent(SharedContainer.snapshotFileName, isDirectory: false)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @discardableResult
    func save(_ snapshot: PetSnapshot) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            assertionFailure("Snapshot write failed: \(error)")
            return false
        }
    }

    /// Returns `nil` for a missing file, unreadable data, or a schema from a
    /// future/older build. Callers fall back to a placeholder rather than
    /// guessing at a partial decode.
    func load() -> PetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? Self.decoder.decode(PetSnapshot.self, from: data) else { return nil }
        guard snapshot.schemaVersion == PetSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
