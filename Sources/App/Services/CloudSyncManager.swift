import CloudKit
import Foundation
import Observation

/// Optional iCloud sync.
///
/// Nothing in the app waits for this. If iCloud is unavailable — no account, no
/// entitlement, or the user simply left the switch off — the app runs entirely
/// from the local SwiftData store. Sync is a convenience layered on top, exactly
/// as the product spec requires.
@MainActor
@Observable
final class CloudSyncManager {
    enum Status: Equatable {
        case unavailable(String)
        case idle
        case syncing
        case synced(Date)
        case failed(String)

        var text: String {
            switch self {
            case .unavailable(let reason): "不可用：\(reason)"
            case .idle:                    "未同步"
            case .syncing:                 "同步中…"
            case .synced(let date):        "已同步 \(date.formatted(.dateTime.hour().minute()))"
            case .failed(let reason):      "失败：\(reason)"
            }
        }
    }

    private static let recordType = "MochiPet"
    private static let recordName = "mochi.primary.pet"
    private static let payloadKey = "payload"

    private(set) var status: Status = .unavailable("未启用")
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "mochi.cloudSync.enabled"

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        refreshAvailability()
    }

    /// `ubiquityIdentityToken` is the only reliable, non-throwing way to know
    /// whether iCloud is usable. Touching `CKContainer` without the entitlement
    /// raises an Objective-C exception, so it is never reached before this check.
    private var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func refreshAvailability() {
        guard isEnabled else {
            status = .unavailable("未启用")
            return
        }
        guard hasICloudAccount else {
            status = .unavailable("未登录 iCloud 或缺少容器权限")
            return
        }
        if case .unavailable = status { status = .idle }
        if case .idle = status { return }
    }

    func push(_ pet: PetState) async {
        guard isEnabled else { return }
        guard hasICloudAccount else {
            status = .unavailable("未登录 iCloud 或缺少容器权限")
            return
        }

        status = .syncing
        do {
            let container = CKContainer.default()
            let database = container.privateCloudDatabase
            let recordID = CKRecord.ID(recordName: Self.recordName)
            let payload = try JSONEncoder.mochi.encode(pet)

            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch {
                record = CKRecord(recordType: Self.recordType, recordID: recordID)
            }
            record[Self.payloadKey] = payload as NSData
            record["updatedAt"] = pet.lastSimulatedAt as NSDate

            _ = try await database.save(record)
            status = .synced(Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Returns the remote pet when the remote copy is newer than the local one.
    func pullIfNewerThan(_ localDate: Date) async -> PetState? {
        guard isEnabled, hasICloudAccount else { return nil }
        do {
            let database = CKContainer.default().privateCloudDatabase
            let record = try await database.record(for: .init(recordName: Self.recordName))
            guard let data = record[Self.payloadKey] as? Data,
                  let remote = try? JSONDecoder.mochi.decode(PetState.self, from: data) else {
                return nil
            }
            return remote.lastSimulatedAt > localDate ? remote : nil
        } catch {
            status = .failed(error.localizedDescription)
            return nil
        }
    }
}

extension JSONEncoder {
    static let mochi: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let mochi: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
