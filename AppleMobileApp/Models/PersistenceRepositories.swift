import Foundation
import SwiftData

struct LocalDataSnapshot {
    var entries: [LogEntry]
    var lists: [SakhyaList]
    var recentlyDeleted: [DeletedEntry]
}

@MainActor
protocol TimelineRepository {
    func loadEntries() throws -> [LogEntry]
    func loadRecentlyDeleted() throws -> [DeletedEntry]
    func save(entries: [LogEntry], recentlyDeleted: [DeletedEntry]) throws
}

enum SyncEntityType: String, Codable {
    case timelineEntry
    case list
}

enum SyncOperationKind: String, Codable {
    case upsert
    case delete
}

struct PendingSyncOperation: Identifiable, Hashable {
    var id: UUID
    var entityID: UUID
    var entityType: SyncEntityType
    var operation: SyncOperationKind
    var payload: Data?
    var createdAt: Date
    var attemptCount: Int
}

@MainActor
protocol SyncOutboxRepository {
    func pendingOperations(limit: Int) throws -> [PendingSyncOperation]
    func completeOperation(id: UUID) throws
    func failOperation(id: UUID, error: String) throws
}

@MainActor
protocol ListRepository {
    func loadLists() throws -> [SakhyaList]
    func save(lists: [SakhyaList]) throws
}

@MainActor
protocol MigrationRepository {
    var isInitialized: Bool { get }
    var schemaVersion: Int { get }
    func markInitialized()
}

@Model
final class TimelineRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var category: String
    var title: String
    var payload: Data
    var note: String?
    var amount: Double?
    var durationMinutes: Int?
    var mood: Int?
    var status: String?
    var attachmentFilename: String?
    var audioAttachmentFilename: String?
    var lifeArea: String?
    var deviceSource: String?
    var listKind: String?
    var listID: UUID?
    var dueDate: Date?
    var completed: Bool?
    var fitnessSource: String?
    var externalIdentifier: String?
    var appleReminderIdentifier: String?
    var isSampleData: Bool?
    var calendarStartDate: Date?
    var calendarEndDate: Date?
    var calendarTitle: String?
    var calendarLocation: String?
    var reminderLeadMinutes: Int?
    var appleCalendarEventIdentifier: String?
    var createdAt: Date?
    var updatedAt: Date?
    var revision: Int?
    var modifiedByDevice: String?

    init(entry: LogEntry, payload: Data) {
        id = entry.id
        timestamp = entry.timestamp
        category = entry.category.rawValue
        title = entry.title
        self.payload = payload
        apply(entry, isNew: true)
    }

    func apply(_ entry: LogEntry, isNew: Bool = false) {
        timestamp = entry.timestamp
        category = entry.category.rawValue
        title = entry.title
        note = entry.note
        amount = entry.amount
        durationMinutes = entry.durationMinutes
        mood = entry.mood
        status = entry.status?.rawValue
        attachmentFilename = entry.attachmentFilename
        audioAttachmentFilename = entry.audioAttachmentFilename
        lifeArea = entry.lifeArea?.rawValue
        deviceSource = entry.deviceSource?.rawValue
        listKind = entry.listKind?.rawValue
        listID = entry.listID
        dueDate = entry.dueDate
        completed = entry.completed
        fitnessSource = entry.fitnessSource
        externalIdentifier = entry.externalIdentifier
        appleReminderIdentifier = entry.appleReminderIdentifier
        isSampleData = entry.isSampleData
        calendarStartDate = entry.calendarStartDate
        calendarEndDate = entry.calendarEndDate
        calendarTitle = entry.calendarTitle
        calendarLocation = entry.calendarLocation
        reminderLeadMinutes = entry.reminderLeadMinutes
        appleCalendarEventIdentifier = entry.appleCalendarEventIdentifier
        if isNew || createdAt == nil { createdAt = .now }
        updatedAt = .now
        revision = (revision ?? 0) + 1
        modifiedByDevice = DeviceIdentity.current
    }
}

@Model
final class ListRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var kind: String
    var access: String
    var payload: Data
    var ownerName: String?
    var collaborationStatus: String?
    var cloudShareRecordName: String?
    var isDefault: Bool?
    var membersPayload: Data?
    var createdAt: Date?
    var updatedAt: Date?
    var revision: Int?
    var modifiedByDevice: String?

    init(list: SakhyaList, payload: Data) {
        id = list.id
        name = list.name
        kind = list.kind.rawValue
        access = list.access.rawValue
        self.payload = payload
        apply(list, isNew: true)
    }

    func apply(_ list: SakhyaList, isNew: Bool = false) {
        name = list.name
        kind = list.kind.rawValue
        access = list.access.rawValue
        ownerName = list.ownerName
        collaborationStatus = list.collaborationStatus.rawValue
        cloudShareRecordName = list.cloudShareRecordName
        isDefault = list.isDefault
        membersPayload = try? JSONEncoder().encode(list.members)
        if isNew || createdAt == nil { createdAt = .now }
        updatedAt = .now
        revision = (revision ?? 0) + 1
        modifiedByDevice = DeviceIdentity.current
    }
}

@Model
final class SyncOutboxRecord {
    @Attribute(.unique) var id: UUID
    var entityID: UUID
    var entityType: String
    var operation: String
    var payload: Data?
    var createdAt: Date
    var attemptCount: Int
    var lastError: String?
    var nextAttemptAt: Date?

    init(entityID: UUID, entityType: SyncEntityType, operation: SyncOperationKind, payload: Data?) {
        id = UUID()
        self.entityID = entityID
        self.entityType = entityType.rawValue
        self.operation = operation.rawValue
        self.payload = payload
        createdAt = .now
        attemptCount = 0
    }
}

enum DeviceIdentity {
    static let current: String = {
        let key = "sakhya.device.identifier"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }()
}

@Model
final class DeletedTimelineRecord {
    @Attribute(.unique) var id: UUID
    var deletedAt: Date
    var payload: Data

    init(value: DeletedEntry, payload: Data) {
        id = value.id
        deletedAt = value.deletedAt
        self.payload = payload
    }
}

@Model
final class StorageMetadataRecord {
    @Attribute(.unique) var key: String
    var boolValue: Bool?
    var dateValue: Date?
    var intValue: Int?

    init(key: String, boolValue: Bool? = nil, dateValue: Date? = nil, intValue: Int? = nil) {
        self.key = key
        self.boolValue = boolValue
        self.dateValue = dateValue
        self.intValue = intValue
    }
}

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            TimelineRecord.self,
            ListRecord.self,
            DeletedTimelineRecord.self,
            StorageMetadataRecord.self,
            SyncOutboxRecord.self,
            SystemWorkspaceRecord.self
        ])
        let databaseDirectory = URL.applicationSupportDirectory
            .appending(path: "Sakhya/Database", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: databaseDirectory.path
        )
        #endif
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                "Sakhya-Preview",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "Sakhya",
                schema: schema,
                url: databaseDirectory.appending(path: "Sakhya.store"),
                cloudKitDatabase: .none
            )
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let fallback = ModelConfiguration(
                "Sakhya-Recovery",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}

@MainActor
final class SwiftDataTimelineRepository: TimelineRepository, MigrationRepository, SyncOutboxRepository {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let initializationKey = "swiftdata.initialized.v1"
    private let schemaVersionKey = "swiftdata.schema-version"
    private let currentSchemaVersion = 2
    private var cachedEntries: [UUID: LogEntry] = [:]
    private var cachedDeleted: [UUID: DeletedEntry] = [:]

    init(container: ModelContainer) {
        context = container.mainContext
        context.autosaveEnabled = false
    }

    var isInitialized: Bool {
        let key = initializationKey
        let descriptor = FetchDescriptor<StorageMetadataRecord>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor).first?.boolValue) == true
    }

    var schemaVersion: Int {
        let key = schemaVersionKey
        let descriptor = FetchDescriptor<StorageMetadataRecord>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor).first?.intValue) ?? 1
    }

    func markInitialized() {
        let key = initializationKey
        let descriptor = FetchDescriptor<StorageMetadataRecord>(predicate: #Predicate { $0.key == key })
        if let record = try? context.fetch(descriptor).first {
            record.boolValue = true
        } else {
            context.insert(StorageMetadataRecord(key: key, boolValue: true))
        }
        let versionKey = schemaVersionKey
        let versionDescriptor = FetchDescriptor<StorageMetadataRecord>(predicate: #Predicate { $0.key == versionKey })
        if let version = try? context.fetch(versionDescriptor).first {
            version.intValue = currentSchemaVersion
        } else {
            context.insert(StorageMetadataRecord(key: versionKey, intValue: currentSchemaVersion))
        }
        try? context.save()
    }

    func loadEntries() throws -> [LogEntry] {
        let descriptor = FetchDescriptor<TimelineRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        var backfilled = false
        let values = try context.fetch(descriptor).compactMap { record -> LogEntry? in
            guard let entry = try? decoder.decode(LogEntry.self, from: record.payload) else { return nil }
            if record.revision == nil {
                record.apply(entry, isNew: true)
                backfilled = true
            }
            return entry
        }
        if backfilled { try context.save() }
        if schemaVersion < currentSchemaVersion { markInitialized() }
        cachedEntries = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        return values
    }

    func loadRecentlyDeleted() throws -> [DeletedEntry] {
        let descriptor = FetchDescriptor<DeletedTimelineRecord>(sortBy: [SortDescriptor(\.deletedAt, order: .reverse)])
        let values = try context.fetch(descriptor).compactMap { try? decoder.decode(DeletedEntry.self, from: $0.payload) }
        cachedDeleted = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        return values
    }

    func save(entries: [LogEntry], recentlyDeleted: [DeletedEntry]) throws {
        try reconcileEntries(entries)
        try reconcileDeleted(recentlyDeleted)
        try context.save()
    }

    func pendingOperations(limit: Int = 100) throws -> [PendingSyncOperation] {
        let now = Date.now
        let descriptor = FetchDescriptor<SyncOutboxRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor)
            .filter { $0.nextAttemptAt == nil || $0.nextAttemptAt! <= now }
            .prefix(limit)
            .compactMap { record in
            guard let entityType = SyncEntityType(rawValue: record.entityType),
                  let operation = SyncOperationKind(rawValue: record.operation) else { return nil }
            return PendingSyncOperation(
                id: record.id,
                entityID: record.entityID,
                entityType: entityType,
                operation: operation,
                payload: record.payload,
                createdAt: record.createdAt,
                attemptCount: record.attemptCount
            )
        }
    }

    func completeOperation(id: UUID) throws {
        let descriptor = FetchDescriptor<SyncOutboxRecord>(predicate: #Predicate { $0.id == id })
        if let record = try context.fetch(descriptor).first { context.delete(record) }
        try context.save()
    }

    func failOperation(id: UUID, error: String) throws {
        let descriptor = FetchDescriptor<SyncOutboxRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        record.attemptCount += 1
        record.lastError = error
        let delay = min(pow(2, Double(record.attemptCount)) * 30, 3_600)
        record.nextAttemptAt = Date.now.addingTimeInterval(delay)
        try context.save()
    }

    private func reconcileEntries(_ values: [LogEntry]) throws {
        let existing = try context.fetch(FetchDescriptor<TimelineRecord>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let retained = Set(values.map(\.id))
        for record in existing where !retained.contains(record.id) {
            context.delete(record)
            enqueue(entityID: record.id, type: .timelineEntry, operation: .delete, payload: nil)
        }
        for entry in values {
            guard cachedEntries[entry.id] != entry else { continue }
            let payload = try encoder.encode(entry)
            if let record = byID[entry.id] {
                record.apply(entry)
                record.payload = payload
            } else {
                context.insert(TimelineRecord(entry: entry, payload: payload))
            }
            enqueue(entityID: entry.id, type: .timelineEntry, operation: .upsert, payload: payload)
        }
        cachedEntries = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private func enqueue(entityID: UUID, type: SyncEntityType, operation: SyncOperationKind, payload: Data?) {
        guard isInitialized else { return }
        let typeValue = type.rawValue
        let operationValue = operation.rawValue
        let descriptor = FetchDescriptor<SyncOutboxRecord>(predicate: #Predicate {
            $0.entityID == entityID && $0.entityType == typeValue
        })
        if let existing = try? context.fetch(descriptor).first {
            existing.operation = operationValue
            existing.payload = payload
            existing.createdAt = .now
            existing.attemptCount = 0
            existing.lastError = nil
            existing.nextAttemptAt = nil
        } else {
            context.insert(SyncOutboxRecord(entityID: entityID, entityType: type, operation: operation, payload: payload))
        }
    }

    private func reconcileDeleted(_ values: [DeletedEntry]) throws {
        let existing = try context.fetch(FetchDescriptor<DeletedTimelineRecord>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let retained = Set(values.map(\.id))
        for record in existing where !retained.contains(record.id) { context.delete(record) }
        for value in values {
            guard cachedDeleted[value.id] != value else { continue }
            let payload = try encoder.encode(value)
            if let record = byID[value.id] {
                record.deletedAt = value.deletedAt
                record.payload = payload
            } else {
                context.insert(DeletedTimelineRecord(value: value, payload: payload))
            }
        }
        cachedDeleted = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }
}

@MainActor
final class SwiftDataListRepository: ListRepository {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedLists: [UUID: SakhyaList] = [:]

    init(container: ModelContainer) {
        context = container.mainContext
    }

    func loadLists() throws -> [SakhyaList] {
        var backfilled = false
        let values = try context.fetch(FetchDescriptor<ListRecord>()).compactMap { record -> SakhyaList? in
            guard let list = try? decoder.decode(SakhyaList.self, from: record.payload) else { return nil }
            if record.revision == nil {
                record.apply(list, isNew: true)
                backfilled = true
            }
            return list
        }
        if backfilled { try context.save() }
        cachedLists = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        return values
    }

    func save(lists: [SakhyaList]) throws {
        let existing = try context.fetch(FetchDescriptor<ListRecord>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let retained = Set(lists.map(\.id))
        for record in existing where !retained.contains(record.id) {
            context.delete(record)
            enqueue(entityID: record.id, operation: .delete, payload: nil)
        }
        for list in lists {
            guard cachedLists[list.id] != list else { continue }
            let payload = try encoder.encode(list)
            if let record = byID[list.id] {
                record.apply(list)
                record.payload = payload
            } else {
                context.insert(ListRecord(list: list, payload: payload))
            }
            enqueue(entityID: list.id, operation: .upsert, payload: payload)
        }
        cachedLists = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        try context.save()
    }

    private func enqueue(entityID: UUID, operation: SyncOperationKind, payload: Data?) {
        let initializationKey = "swiftdata.initialized.v1"
        let metadataDescriptor = FetchDescriptor<StorageMetadataRecord>(predicate: #Predicate { $0.key == initializationKey })
        guard (try? context.fetch(metadataDescriptor).first?.boolValue) == true else { return }
        let typeValue = SyncEntityType.list.rawValue
        let operationValue = operation.rawValue
        let descriptor = FetchDescriptor<SyncOutboxRecord>(predicate: #Predicate {
            $0.entityID == entityID && $0.entityType == typeValue
        })
        if let existing = try? context.fetch(descriptor).first {
            existing.operation = operationValue
            existing.payload = payload
            existing.createdAt = .now
            existing.attemptCount = 0
            existing.lastError = nil
            existing.nextAttemptAt = nil
        } else {
            context.insert(SyncOutboxRecord(entityID: entityID, entityType: .list, operation: operation, payload: payload))
        }
    }
}
