import CloudKit
import Foundation
import Security

struct DeletedEntry: Identifiable, Codable, Hashable {
    var id: UUID { entry.id }
    var entry: LogEntry
    var deletedAt: Date
}

struct CloudSnapshot: Codable {
    var entries: [LogEntry]
    var lists: [AsitraList]
    var recentlyDeleted: [DeletedEntry]
    var attachments: [String: Data]
    var updatedAt: Date
    var version = 1
}

enum CloudSyncService {
    private static let container = CKContainer(identifier: "iCloud.com.devganatra.sakhya")
    private static let recordID = CKRecord.ID(recordName: "primary-snapshot")
    // CloudKit record identifiers are permanent compatibility contracts.
    private static let recordType = "SakhyaSnapshot"

    static var isConfigured: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let containers = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) as? [String] else { return false }
        return containers.contains("iCloud.com.devganatra.sakhya")
        #else
        // iOS does not expose the SecTask entitlement APIs. The iCloud container is
        // declared by the target's entitlements and CloudKit validates availability
        // when accountStatus() or a database operation is performed.
        return true
        #endif
    }

    static func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    static func fetch() async throws -> CloudSnapshot? {
        do {
            let record = try await container.privateCloudDatabase.record(for: recordID)
            guard let asset = record["archive"] as? CKAsset, let fileURL = asset.fileURL else { return nil }
            return try JSONDecoder().decode(CloudSnapshot.self, from: Data(contentsOf: fileURL))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    static func save(_ snapshot: CloudSnapshot) async throws {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent("SakhyaCloudSnapshot.json")
        var writeOptions: Data.WritingOptions = .atomic
        #if os(iOS)
        writeOptions.insert(.completeFileProtection)
        #endif
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: writeOptions)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let database = container.privateCloudDatabase
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record["archive"] = CKAsset(fileURL: fileURL)
        record["updatedAt"] = snapshot.updatedAt as CKRecordValue
        record["version"] = snapshot.version as CKRecordValue
        _ = try await database.save(record)
    }

    static func deleteCloudCopy() async throws {
        do {
            _ = try await container.privateCloudDatabase.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }
}

enum CloudRecordSyncService {
    private static let container = CKContainer(identifier: "iCloud.com.devganatra.sakhya")

    static func apply(_ operation: PendingSyncOperation) async throws {
        let database = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "\(operation.entityType.rawValue)-\(operation.entityID.uuidString)")

        if operation.operation == .delete {
            do {
                _ = try await database.deleteRecord(withID: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                return
            }
            return
        }

        guard let payload = operation.payload else { return }
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            let type = operation.entityType == .timelineEntry ? "SakhyaTimelineEntry" : "SakhyaList"
            record = CKRecord(recordType: type, recordID: recordID)
        }
        record["entityID"] = operation.entityID.uuidString as CKRecordValue
        record["payload"] = payload as CKRecordValue
        record["updatedAt"] = Date.now as CKRecordValue
        record["modifiedByDevice"] = DeviceIdentity.current as CKRecordValue
        _ = try await database.save(record)
    }
}

@MainActor
enum CloudRecordSyncEngine {
    static func flush(_ repository: SyncOutboxRepository) async {
        guard CloudSyncService.isConfigured else { return }
        let operations = (try? repository.pendingOperations(limit: 100)) ?? []
        for operation in operations {
            do {
                try await CloudRecordSyncService.apply(operation)
                try repository.completeOperation(id: operation.id)
            } catch {
                try? repository.failOperation(id: operation.id, error: error.localizedDescription)
            }
        }
    }
}

enum CloudSyncError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        "CloudKit requires a signed build with the Asitra iCloud container entitlement."
    }
}
