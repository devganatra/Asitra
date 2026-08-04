import Foundation
import CloudKit
import ImageIO
import Observation
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

@MainActor
@Observable
final class AppModel {
    var selectedSection: AppSection? = .today
    var notificationsEnabled = true
    var syncEnabled = UserDefaults.standard.object(forKey: "sakhya.icloud.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: "sakhya.icloud.enabled") }
    }
    var keepsDeletedEntries = UserDefaults.standard.object(forKey: "sakhya.trash.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepsDeletedEntries, forKey: "sakhya.trash.enabled") }
    }
    private(set) var cloudStatus = "Checking iCloud…"
    private(set) var lastCloudSync: Date?
    private(set) var isSyncingCloud = false
    private(set) var isImportingFinancialData = false
    private(set) var financialDataStatus = "Not connected"
    private(set) var lastFinancialImport: Date?
    var isFinancialDataAvailable: Bool { financialDataProvider.isAvailable }
    var appleRemindersEnabled: Bool {
        get { calendarFeature.remindersEnabled }
        set { calendarFeature.setRemindersEnabled(newValue) }
    }
    var appleCalendarEnabled: Bool {
        get { calendarFeature.calendarEnabled }
        set { calendarFeature.setCalendarEnabled(newValue) }
    }
    var appleRemindersStatus: String { calendarFeature.remindersStatus }
    var appleCalendarStatus: String { calendarFeature.calendarStatus }
    var appleRemindersError: String? { calendarFeature.errorMessage }
    var isImportingFitness: Bool { healthFeature.isImporting }
    var lastFitnessImport: Date? { healthFeature.lastImport }
    private(set) var entries: [LogEntry] {
        get { timelineFeature.entries }
        set { timelineFeature.entries = newValue }
    }
    private(set) var lists: [AsitraList] = []
    private(set) var recentlyDeleted: [DeletedEntry] {
        get { timelineFeature.recentlyDeleted }
        set { timelineFeature.recentlyDeleted = newValue }
    }

    let timelineFeature: TimelineFeatureModel
    let calendarFeature: CalendarFeatureModel
    let healthFeature: HealthFeatureModel
    let systemFeature: SystemFeatureModel
    private let timelineRepository: SwiftDataTimelineRepository
    private let listRepository: SwiftDataListRepository
    private let calendarRepository: CalendarRepository
    private let healthRepository: HealthRepository
    private let sharedListRepository: SharedListRepository
    private let captureEntryUseCase: CaptureTimelineEntryUseCase
    private let importHealthUseCase: ImportHealthEntriesUseCase
    private let financialDataProvider: any FinancialDataProvider

    private let storageKey = "daily-log.entries.v2"
    private let listsStorageKey = "sakhya.lists.v1"
    private let legacyStorageKey = "daily-log.entries.v1"
    private let lastFitnessImportKey = "sakhya.fitness.last-import"
    private let legacyFitnessImportKey = "sakha.fitness.last-import"
    private let deletedStorageKey = "sakhya.deleted.v1"
    private let lastCloudSyncKey = "sakhya.icloud.last-sync"
    private let localModifiedKey = "sakhya.local.modified"
    private let sampleDataKey = "sakhya.sample-data.loaded"
    private let lastFinancialImportKey = "sakhya.finance.last-import"
    private var cloudSyncTask: Task<Void, Never>?

    convenience init(container: ModelContainer = PersistenceController.makeContainer()) {
        self.init(environment: .live(container: container))
    }

    init(environment: AppEnvironment) {
        let defaults = UserDefaults.standard
        let timelineRepository = environment.timelineRepository
        let listRepository = environment.listRepository
        self.timelineRepository = timelineRepository
        self.listRepository = listRepository
        timelineFeature = TimelineFeatureModel(repository: timelineRepository)
        calendarFeature = CalendarFeatureModel(defaults: defaults)
        healthFeature = HealthFeatureModel(defaults: defaults)
        systemFeature = SystemFeatureModel(
            repository: environment.systemRepository,
            engine: environment.todaySystemEngine
        )
        calendarRepository = environment.calendarRepository
        healthRepository = environment.healthRepository
        sharedListRepository = environment.sharedListRepository
        captureEntryUseCase = environment.captureEntry
        importHealthUseCase = environment.importHealth
        financialDataProvider = environment.financialDataProvider

        if timelineRepository.isInitialized {
            try? timelineFeature.load()
            lists = (try? listRepository.loadLists()).flatMap { $0.isEmpty ? nil : $0 } ?? AsitraList.defaults
        } else {
            if let data = defaults.data(forKey: listsStorageKey),
               let savedLists = try? JSONDecoder().decode([AsitraList].self, from: data),
               !savedLists.isEmpty {
                lists = savedLists
            } else {
                lists = AsitraList.defaults
            }
            let storedData = defaults.data(forKey: storageKey) ?? defaults.data(forKey: legacyStorageKey)
            if let storedData,
               let savedEntries = try? JSONDecoder().decode([LogEntry].self, from: storedData) {
                entries = savedEntries
            } else {
                entries = LogEntry.examples
            }
            if let data = defaults.data(forKey: deletedStorageKey),
               let deleted = try? JSONDecoder().decode([DeletedEntry].self, from: data) {
                recentlyDeleted = deleted
            }
        }
        lastCloudSync = defaults.object(forKey: lastCloudSyncKey) as? Date
        lastFinancialImport = defaults.object(forKey: lastFinancialImportKey) as? Date
        if lastFinancialImport != nil {
            financialDataStatus = "Connected"
        } else if !financialDataProvider.isAvailable {
            financialDataStatus = "Available on supported iPhone regions"
        }
        migrateListAssignments()
        if !timelineRepository.isInitialized {
            if defaults.object(forKey: sampleDataKey) == nil {
                addSampleData()
            } else {
                save(markModified: false)
            }
            timelineRepository.markInitialized()
        }
        Task { await prepareCloudSync() }
        if appleCalendarEnabled, appleCalendarStatus == "Connected" {
            Task { await syncUnsyncedEntriesToAppleCalendar() }
        }
    }

    func add(
        _ entry: LogEntry,
        photoData: Data? = nil,
        audioData: Data? = nil,
        syncToCalendar: Bool = false
    ) {
        var storedEntry = entry
        if storedEntry.category == .list, storedEntry.listID == nil {
            storedEntry.listID = defaultList(for: storedEntry.listKind ?? .task)?.id
        }
        if let photoData {
            storedEntry.attachmentFilename = saveAttachment(photoData, id: entry.id, extension: "image")
        }
        if let audioData {
            storedEntry.audioAttachmentFilename = saveAttachment(audioData, id: entry.id, extension: "m4a")
        }
        entries.append(storedEntry)
        entries.sort { $0.timestamp > $1.timestamp }
        save()
        if syncToCalendar, appleCalendarEnabled, storedEntry.isSampleData != true {
            Task { await syncToAppleCalendar(storedEntry) }
        }
        if storedEntry.category == .list, storedEntry.listKind == .reminder, appleRemindersEnabled {
            syncToAppleReminders(storedEntry)
        } else if storedEntry.category == .list, let dueDate = storedEntry.dueDate {
            scheduleNotification(for: storedEntry, at: dueDate)
        }
    }

    func addCapturedText(
        _ text: String,
        on date: Date = .now,
        photoData: Data? = nil,
        audioData: Data? = nil,
        captureNote: String = "",
        calendarOverride: CalendarCaptureOverride? = nil
    ) {
        let suggestion = SmartCapture(text: text)
        let destination: AsitraList?
        if let kind = suggestion.listKind {
            destination = suggestedList(for: text, kind: kind)
        } else {
            destination = nil
        }
        guard let entry = captureEntryUseCase.makeEntry(
            text: text,
            selectedDate: date,
            destination: destination,
            deviceSource: currentDeviceSource,
            captureNote: captureNote,
            calendarOverride: calendarOverride
        ) else { return }
        add(
            entry,
            photoData: photoData,
            audioData: audioData,
            syncToCalendar: calendarOverride != nil || entry.calendarStartDate != nil
        )
    }

    @discardableResult
    func importAppleWalletSpending() async -> Int {
        guard !isImportingFinancialData else { return 0 }
        isImportingFinancialData = true
        financialDataStatus = "Waiting for Apple Wallet…"
        defer { isImportingFinancialData = false }

        let initialStart = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .distantPast
        let startDate = lastFinancialImport.map {
            Calendar.current.date(byAdding: .day, value: -7, to: $0) ?? $0
        } ?? initialStart

        do {
            let batch = try await financialDataProvider.requestAndFetchTransactions(since: startDate)
            let knownIdentifiers = Set(entries.compactMap(\.externalIdentifier))
            let newTransactions = batch.transactions.filter {
                !knownIdentifiers.contains("financekit:\($0.id.uuidString)")
            }
            let importedEntries = newTransactions.map { transaction in
                LogEntry(
                    timestamp: transaction.date,
                    category: .expense,
                    title: transaction.merchantName,
                    note: transaction.transactionDescription,
                    amount: transaction.amount,
                    lifeArea: .personal,
                    deviceSource: .phone,
                    fitnessSource: "Apple Wallet",
                    externalIdentifier: "financekit:\(transaction.id.uuidString)",
                    financialAccountID: transaction.account.id,
                    financialAccountName: transaction.account.displayName,
                    financialInstitutionName: transaction.account.institutionName,
                    financialCurrencyCode: transaction.currencyCode,
                    merchantCategoryCode: transaction.merchantCategoryCode,
                    financialTransactionStatus: transaction.status
                )
            }
            if !importedEntries.isEmpty {
                entries.append(contentsOf: importedEntries)
                entries.sort { $0.timestamp > $1.timestamp }
                save()
            }
            lastFinancialImport = .now
            UserDefaults.standard.set(lastFinancialImport, forKey: lastFinancialImportKey)
            financialDataStatus = newTransactions.isEmpty
                ? "Connected · Everything is up to date"
                : "Connected · Added \(newTransactions.count) transactions"
            return newTransactions.count
        } catch {
            financialDataStatus = error.localizedDescription
            return 0
        }
    }

    func update(_ entry: LogEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let previous = entries[index]
        var storedEntry = entry
        if storedEntry.calendarStartDate == nil {
            storedEntry.calendarEndDate = nil
        }
        entries[index] = storedEntry
        entries.sort { $0.timestamp > $1.timestamp }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [entry.id.uuidString])
        if storedEntry.category == .list, storedEntry.appleReminderIdentifier == nil, let dueDate = storedEntry.dueDate {
            scheduleNotification(for: storedEntry, at: dueDate)
        }
        save()

        if let identifier = previous.appleCalendarEventIdentifier, storedEntry.calendarStartDate == nil {
            Task {
                do {
                    try AppleReminderService.shared.deleteCalendarEvent(identifier: identifier)
                    guard let updatedIndex = entries.firstIndex(where: { $0.id == storedEntry.id }) else { return }
                    entries[updatedIndex].appleCalendarEventIdentifier = nil
                    save()
                    calendarFeature.update(calendarStatus: "Connected")
                } catch {
                    calendarFeature.setError(error.localizedDescription)
                }
            }
        } else if let identifier = storedEntry.appleCalendarEventIdentifier {
            Task {
                do {
                    let start = storedEntry.calendarStartDate ?? storedEntry.timestamp
                    let end = storedEntry.calendarEndDate
                        ?? start.addingTimeInterval(TimeInterval(max(storedEntry.durationMinutes ?? 15, 1) * 60))
                    try AppleReminderService.shared.updateCalendarEvent(
                        identifier: identifier,
                        title: storedEntry.calendarTitle ?? calendarTitle(from: storedEntry.title),
                        location: storedEntry.calendarLocation,
                        notes: storedEntry.note.isEmpty ? "Updated from Asitra" : "Updated from Asitra\n\n\(storedEntry.note)",
                        startDate: start,
                        endDate: end,
                        reminderLeadMinutes: storedEntry.reminderLeadMinutes
                    )
                    calendarFeature.update(calendarStatus: "Connected")
                } catch {
                    calendarFeature.setError(error.localizedDescription)
                }
            }
        } else if storedEntry.calendarStartDate != nil, appleCalendarEnabled {
            Task { await syncToAppleCalendar(storedEntry) }
        }

        if previous.category == .list, storedEntry.category != .list,
           let identifier = previous.appleReminderIdentifier {
            Task {
                do {
                    try AppleReminderService.shared.deleteReminder(identifier: identifier)
                    guard let updatedIndex = entries.firstIndex(where: { $0.id == storedEntry.id }) else { return }
                    entries[updatedIndex].appleReminderIdentifier = nil
                    save()
                    calendarFeature.update(remindersStatus: "Connected")
                } catch {
                    calendarFeature.setError(error.localizedDescription)
                }
            }
        } else if storedEntry.category == .list, let identifier = storedEntry.appleReminderIdentifier {
            Task {
                do {
                    try AppleReminderService.shared.updateReminder(
                        identifier: identifier,
                        title: storedEntry.title,
                        notes: storedEntry.note,
                        dueDate: storedEntry.dueDate
                    )
                    calendarFeature.update(remindersStatus: "Connected")
                } catch {
                    calendarFeature.setError(error.localizedDescription)
                }
            }
        }
    }

    func defaultList(for kind: ListKind) -> AsitraList? {
        lists.first { $0.kind == kind && $0.isDefault } ?? lists.first { $0.kind == kind }
    }

    func suggestedList(for text: String, kind: ListKind) -> AsitraList? {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let namedList = lists.first(where: { list in
            guard list.kind == kind, !list.isDefault else { return false }
            let name = list.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return normalized.localizedStandardContains(name)
        }) {
            return namedList
        }
        return defaultList(for: kind)
    }

    func list(withID id: UUID?) -> AsitraList? {
        guard let id else { return nil }
        return lists.first { $0.id == id }
    }

    @discardableResult
    func createList(name: String, kind: ListKind, access: ListAccess) -> UUID {
        let list = AsitraList(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            access: access
        )
        lists.append(list)
        save()
        return list.id
    }

    func updateList(_ list: AsitraList) {
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[index] = list
        for entryIndex in entries.indices where entries[entryIndex].listID == list.id {
            entries[entryIndex].listKind = list.kind
        }
        save()
    }

    func deleteList(_ list: AsitraList) {
        guard !list.isDefault else { return }
        let fallbackID = defaultList(for: list.kind)?.id
        for index in entries.indices where entries[index].listID == list.id {
            entries[index].listID = fallbackID
            entries[index].listKind = list.kind
        }
        lists.removeAll { $0.id == list.id }
        save()
    }

    func prepareSharing(for list: AsitraList) async throws {
        guard list.access == .shared else { return }
        let shareRecordName = try await sharedListRepository.prepareShare(for: list)
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[index].cloudShareRecordName = shareRecordName
        lists[index].collaborationStatus = .active
        save()
    }

    func toggleCompleted(_ entry: LogEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isCompleted.toggle()
        if entries[index].isCompleted {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [entry.id.uuidString])
        } else if entries[index].appleReminderIdentifier == nil, let dueDate = entries[index].dueDate {
            scheduleNotification(for: entries[index], at: dueDate)
        }
        if let identifier = entries[index].appleReminderIdentifier {
            let completed = entries[index].isCompleted
            Task {
                do {
                    try AppleReminderService.shared.setCompleted(completed, identifier: identifier)
                    calendarFeature.update(remindersStatus: AppleReminderService.shared.statusDescription)
                } catch {
                    calendarFeature.setError(error.localizedDescription)
                }
            }
        }
        save()
    }

    func recordCollectionStatus(for entry: LogEntry, title: String, status: EntryStatus) {
        let action: String
        switch (entry.category, status) {
        case (.book, .planned): action = "Want to read \(title)"
        case (.book, .inProgress): action = "Started reading \(title)"
        case (.book, .completed): action = "Finished reading \(title)"
        case (.movie, .planned): action = "Want to watch \(title)"
        case (.movie, .inProgress): action = "Started watching \(title)"
        case (.movie, .completed): action = "Watched \(title)"
        default: action = title
        }

        add(LogEntry(
            timestamp: .now,
            category: entry.category,
            title: action,
            note: "Updated from the \(entry.category.rawValue.lowercased()) list",
            status: status,
            lifeArea: .personal,
            deviceSource: currentDeviceSource
        ))
    }

    func delete(_ entry: LogEntry) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [entry.id.uuidString])
        if keepsDeletedEntries {
            recentlyDeleted.removeAll { $0.id == entry.id }
            recentlyDeleted.insert(DeletedEntry(entry: entry, deletedAt: .now), at: 0)
        } else {
            permanentlyRemoveAttachments(for: entry)
        }
        entries.removeAll { $0.id == entry.id }
        save()
        if let identifier = entry.appleReminderIdentifier {
            Task {
                do {
                    try AppleReminderService.shared.deleteReminder(identifier: identifier)
                } catch {
                    calendarFeature.setError(error.localizedDescription)
                }
            }
        }
        if let identifier = entry.appleCalendarEventIdentifier {
            Task { try? AppleReminderService.shared.deleteCalendarEvent(identifier: identifier) }
        }
    }

    func connectAppleCalendar() async {
        do {
            let granted = try await calendarRepository.requestCalendarAccess()
            calendarFeature.update(calendarStatus: granted ? "Connected" : "Access denied")
            calendarFeature.setError(granted ? nil : "Enable Calendar access in System Settings.")
            if granted { await syncUnsyncedEntriesToAppleCalendar() }
        } catch {
            calendarFeature.update(calendarStatus: "Connection failed")
            calendarFeature.setError(error.localizedDescription)
        }
    }

    func calendarAgenda(on date: Date) -> [CalendarAgendaItem] {
        calendarRepository.agenda(on: date)
    }

    func restore(_ deleted: DeletedEntry) {
        recentlyDeleted.removeAll { $0.id == deleted.id }
        if !entries.contains(where: { $0.id == deleted.id }) { entries.append(deleted.entry) }
        entries.sort { $0.timestamp > $1.timestamp }
        save()
    }

    func restoreAllDeleted() {
        let known = Set(entries.map(\.id))
        entries.append(contentsOf: recentlyDeleted.map(\.entry).filter { !known.contains($0.id) })
        entries.sort { $0.timestamp > $1.timestamp }
        recentlyDeleted = []
        save()
    }

    func emptyRecentlyDeleted() {
        recentlyDeleted.forEach { permanentlyRemoveAttachments(for: $0.entry) }
        recentlyDeleted = []
        save()
    }

    func addSampleData() {
        guard !entries.contains(where: { $0.isSampleData == true }) else { return }
        entries.append(contentsOf: SampleDataFactory.make(days: 30, lists: lists))
        entries.sort { $0.timestamp > $1.timestamp }
        UserDefaults.standard.set(true, forKey: sampleDataKey)
        save()
    }

    func removeSampleData() {
        let samples = entries.filter { $0.isSampleData == true }
        samples.forEach { permanentlyRemoveAttachments(for: $0) }
        entries.removeAll { $0.isSampleData == true }
        recentlyDeleted.removeAll { $0.entry.isSampleData == true }
        UserDefaults.standard.set(false, forKey: sampleDataKey)
        save()
    }

    var sampleEntryCount: Int { entries.filter { $0.isSampleData == true }.count }

    var localStorageDescription: String {
        let bytes = attachmentFilenames.reduce(Int64(0)) { total, filename in
            let url = attachmentURL(for: filename)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return total + size
        }
        return "\(entries.count) SwiftData entries • \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) attachments"
    }

    func syncNow() async {
        guard syncEnabled, !isSyncingCloud else { return }
        guard CloudSyncService.isConfigured else {
            cloudStatus = "Setup required: select your Developer Team"
            return
        }
        isSyncingCloud = true
        cloudStatus = "Syncing…"
        defer { isSyncingCloud = false }
        do {
            let status = try await CloudSyncService.accountStatus()
            guard status == .available else {
                cloudStatus = status == .noAccount ? "Sign in to iCloud" : "iCloud unavailable"
                return
            }
            await CloudRecordSyncEngine.flush(timelineRepository)
            let remote = try await CloudSyncService.fetch()
            let localModified = UserDefaults.standard.object(forKey: localModifiedKey) as? Date ?? .distantPast
            if let remote, lastCloudSync == nil || remote.updatedAt > localModified {
                apply(remote)
            } else {
                try await CloudSyncService.save(makeCloudSnapshot())
            }
            lastCloudSync = .now
            UserDefaults.standard.set(lastCloudSync, forKey: lastCloudSyncKey)
            cloudStatus = "Synced privately"
        } catch {
            cloudStatus = cloudMessage(for: error)
        }
    }

    func clearLocalCopyKeepingCloud() {
        syncEnabled = false
        removeAllLocalAttachments()
        entries = []
        lists = AsitraList.defaults
        recentlyDeleted = []
        lastCloudSync = nil
        UserDefaults.standard.removeObject(forKey: lastCloudSyncKey)
        save()
        cloudStatus = "Local copy cleared • iCloud kept"
    }

    func deleteEverywhere() async throws {
        guard CloudSyncService.isConfigured else { throw CloudSyncError.notConfigured }
        try await CloudSyncService.deleteCloudCopy()
        syncEnabled = false
        removeAllLocalAttachments()
        entries = []
        lists = AsitraList.defaults
        recentlyDeleted = []
        save()
        cloudStatus = "All Asitra data deleted"
    }

    func connectAppleReminders() async {
        do {
            let granted = try await calendarRepository.requestReminderAccess()
            calendarFeature.update(remindersStatus: granted ? "Connected" : "Access denied")
            calendarFeature.setError(granted ? nil : "Enable Reminders access in System Settings.")
        } catch {
            calendarFeature.update(remindersStatus: "Connection failed")
            calendarFeature.setError(error.localizedDescription)
        }
    }

    @discardableResult
    func importFitnessData() async throws -> Int {
        healthFeature.beginImport()
        let imported: [LogEntry]
        do {
            imported = try await healthRepository.importRecentEntries()
        } catch {
            healthFeature.finishImport()
            throw error
        }
        let newEntries = importHealthUseCase.newEntries(from: imported, existing: entries)

        entries.append(contentsOf: newEntries)
        entries.sort { $0.timestamp > $1.timestamp }
        healthFeature.finishImport(at: .now)
        save()
        return newEntries.count
    }

    var connectedFitnessSources: [String] {
        Array(Set(entries.compactMap(\.fitnessSource))).sorted()
    }

    var currentDeviceSource: DeviceSource {
#if os(macOS)
        .mac
#else
        .phone
#endif
    }

    func attachmentData(for entry: LogEntry) -> Data? {
        guard let filename = entry.attachmentFilename else { return nil }
        return try? Data(contentsOf: attachmentURL(for: filename))
    }

    func audioAttachmentURL(for entry: LogEntry) -> URL? {
        guard let filename = entry.audioAttachmentFilename else { return nil }
        let url = attachmentURL(for: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func entries(on date: Date) -> [LogEntry] {
        entries
            .filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func expense(on date: Date) -> Double {
        entries(on: date).compactMap(\.amount).reduce(0, +)
    }

    func activeMinutes(on date: Date) -> Int {
        entries(on: date)
            .filter { $0.category == .fitness }
            .compactMap(\.durationMinutes)
            .reduce(0, +)
    }

    func sleepMinutes(on date: Date) -> Int {
        entries(on: date)
            .filter { $0.category == .sleep }
            .compactMap(\.durationMinutes)
            .reduce(0, +)
    }

    func trackedMinutes(_ area: LifeArea, on date: Date) -> Int {
        entries(on: date)
            .filter { ($0.lifeArea ?? $0.category.defaultLifeArea) == area }
            .compactMap(\.durationMinutes)
            .reduce(0, +)
    }

    func screenMinutes(on date: Date) -> Int {
        entries(on: date)
            .filter { $0.category == .screenTime }
            .compactMap(\.durationMinutes)
            .reduce(0, +)
    }

    func balanceScore(for dates: [Date]) -> Int {
        let work = dates.map { trackedMinutes(.work, on: $0) }.reduce(0, +)
        let personal = dates.map { trackedMinutes(.personal, on: $0) }.reduce(0, +)
        guard work + personal > 0 else { return 0 }
        let workShare = Double(work) / Double(work + personal)
        return max(0, Int((1 - abs(workShare - 0.5) * 2) * 100))
    }

    private var attachmentsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // Preserve the legacy attachment location across the Asitra rebrand.
        let directory = base.appendingPathComponent("Sakhya/Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        return directory
    }

    private var legacyAttachmentsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Dayline/Attachments", isDirectory: true)
    }

    private func attachmentURL(for filename: String) -> URL {
        let current = attachmentsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: current.path) { return current }
        return legacyAttachmentsDirectory.appendingPathComponent(filename)
    }

    private func saveAttachment(_ data: Data, id: UUID, extension fileExtension: String) -> String? {
        let filename = "\(id.uuidString).\(fileExtension)"
        do {
            let storedData = fileExtension == "image" ? optimizedImageData(from: data) ?? data : data
            try storedData.write(
                to: attachmentsDirectory.appendingPathComponent(filename),
                options: protectedWriteOptions
            )
            return filename
        } catch {
            return nil
        }
    }

    private func optimizedImageData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048
              ] as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func save(markModified: Bool = true) {
        try? timelineFeature.persist()
        try? listRepository.save(lists: lists)
        if markModified {
            UserDefaults.standard.set(Date.now, forKey: localModifiedKey)
            scheduleCloudSync()
        }
    }

    private func scheduleCloudSync() {
        guard syncEnabled else { return }
        cloudSyncTask?.cancel()
        cloudSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func prepareCloudSync() async {
        guard CloudSyncService.isConfigured else {
            cloudStatus = "Local only • iCloud setup required"
            return
        }
        do {
            let status = try await CloudSyncService.accountStatus()
            cloudStatus = status == .available ? "Ready to sync" : (status == .noAccount ? "Sign in to iCloud" : "iCloud unavailable")
            if status == .available, syncEnabled { await syncNow() }
        } catch {
            cloudStatus = cloudMessage(for: error)
        }
    }

    private func makeCloudSnapshot() -> CloudSnapshot {
        var files: [String: Data] = [:]
        for filename in attachmentFilenames {
            files[filename] = try? Data(contentsOf: attachmentURL(for: filename))
        }
        return CloudSnapshot(entries: entries, lists: lists, recentlyDeleted: recentlyDeleted, attachments: files.compactMapValues { $0 }, updatedAt: .now)
    }

    private func apply(_ snapshot: CloudSnapshot) {
        entries = snapshot.entries
        lists = snapshot.lists.isEmpty ? AsitraList.defaults : snapshot.lists
        recentlyDeleted = snapshot.recentlyDeleted
        for (filename, data) in snapshot.attachments {
            try? data.write(
                to: attachmentsDirectory.appendingPathComponent(filename),
                options: protectedWriteOptions
            )
        }
        UserDefaults.standard.set(snapshot.updatedAt, forKey: localModifiedKey)
        save(markModified: false)
    }

    private var attachmentFilenames: Set<String> {
        Set((entries + recentlyDeleted.map(\.entry)).flatMap { [$0.attachmentFilename, $0.audioAttachmentFilename].compactMap { $0 } })
    }

    private var protectedWriteOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        .atomic
        #endif
    }

    private func permanentlyRemoveAttachments(for entry: LogEntry) {
        [entry.attachmentFilename, entry.audioAttachmentFilename].compactMap { $0 }.forEach { filename in
            let current = attachmentsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: current.path) { try? FileManager.default.removeItem(at: current) }
            let legacy = legacyAttachmentsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: legacy.path) { try? FileManager.default.removeItem(at: legacy) }
        }
    }

    private func removeAllLocalAttachments() {
        attachmentFilenames.forEach { filename in
            let current = attachmentsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: current.path) { try? FileManager.default.removeItem(at: current) }
            let legacy = legacyAttachmentsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: legacy.path) { try? FileManager.default.removeItem(at: legacy) }
        }
    }

    private func cloudMessage(for error: Error) -> String {
        if let cloudError = error as? CKError, cloudError.code == .notAuthenticated { return "Sign in to iCloud" }
        return "Setup required: select your Apple Developer team and iCloud container"
    }

    private func migrateListAssignments() {
        for index in entries.indices where entries[index].category == .list && entries[index].listID == nil {
            let kind = entries[index].listKind ?? .task
            entries[index].listKind = kind
            entries[index].listID = defaultList(for: kind)?.id
        }
    }

    private func scheduleNotification(for entry: LogEntry, at date: Date) {
        guard notificationsEnabled, date > .now else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = entry.listKind?.displayName ?? "Asitra reminder"
            content.body = entry.title
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private func syncToAppleReminders(_ entry: LogEntry) {
        Task {
            do {
                let identifier = try await AppleReminderService.shared.createReminder(
                    title: entry.title,
                    notes: entry.note.isEmpty ? "Created from Asitra" : "\(entry.note)\n\nCreated from Asitra",
                    dueDate: entry.dueDate
                )
                guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
                entries[index].appleReminderIdentifier = identifier
                calendarFeature.update(remindersStatus: "Connected")
                calendarFeature.setError(nil)
                save()
            } catch {
                calendarFeature.update(remindersStatus: "Connection failed")
                calendarFeature.setError(error.localizedDescription)
                if let dueDate = entry.dueDate {
                    scheduleNotification(for: entry, at: dueDate)
                }
            }
        }
    }

    private func syncToAppleCalendar(_ entry: LogEntry) async {
        guard entry.isSampleData != true, entry.appleCalendarEventIdentifier == nil else { return }
        let startDate = entry.calendarStartDate ?? entry.timestamp
        let defaultMinutes = max(entry.durationMinutes ?? 15, 1)
        let endDate = entry.calendarEndDate ?? startDate.addingTimeInterval(TimeInterval(defaultMinutes * 60))
        do {
                let eventID = try await AppleReminderService.shared.createCalendarEvent(
                    title: entry.calendarTitle ?? calendarTitle(from: entry.title),
                    location: entry.calendarLocation,
                    notes: "Created from Asitra\n\n\(entry.title)",
                    startDate: startDate,
                    endDate: endDate,
                    reminderLeadMinutes: entry.reminderLeadMinutes
                )
                guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
                entries[index].appleCalendarEventIdentifier = eventID
                calendarFeature.update(calendarStatus: "Connected")

                if let lead = entry.reminderLeadMinutes, appleRemindersEnabled {
                    let dueDate = startDate.addingTimeInterval(TimeInterval(-lead * 60))
                    let reminderID = try await AppleReminderService.shared.createReminder(
                        title: "Upcoming: \(calendarTitle(from: entry.title))",
                        notes: "Linked to the Asitra meeting at \(startDate.formatted(date: .abbreviated, time: .shortened)).",
                        dueDate: dueDate
                    )
                    entries[index].appleReminderIdentifier = reminderID
                    calendarFeature.update(remindersStatus: "Connected")
                }
                save()
        } catch {
            calendarFeature.update(calendarStatus: "Connection failed")
            calendarFeature.setError(error.localizedDescription)
        }
    }

    private func syncUnsyncedEntriesToAppleCalendar() async {
        let unsynced = entries.filter { $0.isSampleData != true && $0.appleCalendarEventIdentifier == nil }
        for entry in unsynced {
            await syncToAppleCalendar(entry)
        }
    }

    private func calendarTitle(from text: String) -> String {
        let lowered = text.lowercased()
        if let range = lowered.range(of: "meeting") {
            let suffix = text[range.upperBound...]
                .replacingOccurrences(of: #"remind me.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if suffix.lowercased().hasPrefix("with ") { return "Meeting \(suffix)" }
            return "Meeting"
        }
        return text
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case lists = "Lists"
    case collections = "Track"
    case money = "Money"
    case balance = "Balance"
    case settings = "Settings"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .today: "clock"
        case .lists: "checklist"
        case .collections: "chart.line.uptrend.xyaxis"
        case .money: "wallet.bifold"
        case .balance: "circle.lefthalf.filled"
        case .settings: "gearshape"
        }
    }
}

enum LogCategory: String, CaseIterable, Codable, Identifiable {
    case routine = "Routine"
    case work = "Work"
    case expense = "Expense"
    case fitness = "Fitness"
    case sleep = "Sleep"
    case food = "Food"
    case mood = "Mood"
    case screenTime = "Screen Time"
    case list = "List"
    case book = "Book"
    case movie = "Movie"
    case journal = "Journal"
    case idea = "Idea"
    case note = "Note"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .routine: "Habits & Routine"
        case .fitness: "Health & Fitness"
        case .sleep: "Sleep"
        case .mood: "Mindset"
        case .screenTime: "Screen Time"
        case .list: "List & Reminder"
        default: rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .routine: "checkmark.circle"
        case .work: "briefcase"
        case .expense: "creditcard"
        case .fitness: "heart.text.square"
        case .sleep: "bed.double"
        case .food: "fork.knife"
        case .mood: "brain.head.profile"
        case .screenTime: "hourglass"
        case .list: "checklist"
        case .book: "book.closed"
        case .movie: "film"
        case .journal: "book.pages"
        case .idea: "lightbulb"
        case .note: "text.alignleft"
        }
    }

    var defaultLifeArea: LifeArea {
        switch self {
        case .work: .work
        case .sleep: .rest
        default: .personal
        }
    }
}

enum LifeArea: String, CaseIterable, Codable, Identifiable {
    case work = "Work"
    case personal = "Personal"
    case rest = "Rest"

    var id: Self { self }
    var systemImage: String {
        switch self {
        case .work: "briefcase"
        case .personal: "house"
        case .rest: "moon.zzz"
        }
    }
}

enum DeviceSource: String, CaseIterable, Codable, Identifiable {
    case phone = "Phone"
    case tablet = "Tablet"
    case mac = "Mac"
    case web = "Web"
    case offline = "Offline"

    var id: Self { self }
    var systemImage: String {
        switch self {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .mac: "macbook"
        case .web: "globe"
        case .offline: "person"
        }
    }
}

enum EntryStatus: String, CaseIterable, Codable, Identifiable {
    case planned = "Want to"
    case inProgress = "In progress"
    case completed = "Completed"

    var id: Self { self }
}

enum EntryCapability: String, Hashable {
    case edit
    case delete
    case schedule
    case complete
    case amount
    case duration
    case status
    case tripLink
}

extension LogCategory {
    var capabilities: Set<EntryCapability> {
        var result: Set<EntryCapability> = [.edit, .delete, .schedule]
        switch self {
        case .list, .routine:
            result.insert(.complete)
        case .expense:
            result.formUnion([.amount, .tripLink])
        case .work, .fitness, .sleep, .screenTime:
            result.insert(.duration)
        case .book, .movie:
            result.formUnion([.duration, .status])
        case .food, .mood, .journal, .idea, .note:
            break
        }
        return result
    }
}

enum ListKind: String, CaseIterable, Codable, Identifiable {
    case grocery = "Grocery"
    case shopping = "Shopping"
    case reminder = "Reminder"
    case task = "Task"

    var id: Self { self }
    var displayName: String {
        switch self {
        case .grocery: "Groceries"
        case .shopping: "To Buy"
        case .reminder: "Reminders"
        case .task: "Tasks"
        }
    }
    var systemImage: String {
        switch self {
        case .grocery: "cart"
        case .shopping: "bag"
        case .reminder: "bell"
        case .task: "checkmark.circle"
        }
    }
}

enum ListAccess: String, CaseIterable, Codable, Identifiable {
    case privateList = "Private"
    case shared = "Shared"

    var id: Self { self }
    var systemImage: String { self == .privateList ? "lock.fill" : "person.2.fill" }
}

enum ListPermission: String, CaseIterable, Codable, Identifiable {
    case canEdit = "Can edit"
    case viewOnly = "View only"

    var id: Self { self }
}

enum CollaborationStatus: String, Codable {
    case preparing
    case active
}

struct ListMember: Identifiable, Codable, Hashable {
    var id = UUID()
    var displayName: String
    var permission: ListPermission
    var isOwner = false
}

struct AsitraList: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: ListKind
    var access: ListAccess = .privateList
    var ownerName = "You"
    var members: [ListMember] = []
    var collaborationStatus: CollaborationStatus = .preparing
    var cloudShareRecordName: String?
    var isDefault = false

    var isCloudConnected: Bool {
        access == .shared && collaborationStatus == .active && cloudShareRecordName != nil
    }

    static let defaults: [AsitraList] = ListKind.allCases.map { kind in
        AsitraList(name: kind.displayName, kind: kind, isDefault: true)
    }
}

struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var timestamp: Date
    var category: LogCategory
    var title: String
    var note: String = ""
    var amount: Double?
    var durationMinutes: Int?
    var mood: Int?
    var status: EntryStatus?
    var attachmentFilename: String?
    var audioAttachmentFilename: String?
    var lifeArea: LifeArea?
    var deviceSource: DeviceSource?
    var listKind: ListKind?
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
    var trackerID: UUID?
    var financialAccountID: UUID?
    var financialAccountName: String?
    var financialInstitutionName: String?
    var financialCurrencyCode: String?
    var merchantCategoryCode: Int?
    var financialTransactionStatus: String?

    var capabilities: Set<EntryCapability> { category.capabilities }

    var isCompleted: Bool {
        get { completed ?? false }
        set { completed = newValue }
    }

    var collectionDisplayTitle: String {
        guard category == .book || category == .movie else { return title }
        let prefixes: [String] = category == .book
            ? ["want to read ", "started reading ", "finished reading ", "finished ", "reading ", "read ", "book: ", "book "]
            : ["want to watch ", "started watching ", "finished watching ", "watched ", "watching ", "watch ", "movie: ", "movie ", "film: ", "film "]
        let lowered = title.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            let start = title.index(title.startIndex, offsetBy: prefix.count)
            let remainder = title[start...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainder.isEmpty { return remainder }
        }
        return title
    }

    var collectionKey: String {
        collectionDisplayTitle
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    static var examples: [LogEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func time(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: .minute, value: hour * 60 + minute, to: today) ?? today
        }

        return [
            LogEntry(timestamp: time(7, 15), category: .routine, title: "Woke up and completed my morning routine"),
            LogEntry(timestamp: time(9), category: .work, title: "Focused work on Mac", note: "Main priority first", durationMinutes: 180, lifeArea: .work, deviceSource: .mac),
            LogEntry(timestamp: time(12, 40), category: .expense, title: "Bought lunch", amount: 12.50),
            LogEntry(timestamp: time(18, 10), category: .fitness, title: "Evening walk", note: "Felt refreshing", durationMinutes: 35, lifeArea: .personal, deviceSource: .offline),
            LogEntry(timestamp: time(19), category: .screenTime, title: "Used phone after dinner", durationMinutes: 40, lifeArea: .personal, deviceSource: .phone),
            LogEntry(timestamp: time(20), category: .book, title: "Read Atomic Habits", status: .inProgress),
            LogEntry(timestamp: time(21, 30), category: .journal, title: "A calm and productive day", note: "I made time for the work and people that mattered.")
        ]
    }
}

struct CalendarCaptureOverride {
    var title: String
    var location: String?
    var startDate: Date
    var endDate: Date
    var reminderLeadMinutes: Int?
}

struct SmartCapture {
    let category: LogCategory
    let amount: Double?
    let durationMinutes: Int?
    let status: EntryStatus?
    let lifeArea: LifeArea
    let deviceSource: DeviceSource?
    let listKind: ListKind?
    let dueDate: Date?
    let calendarStartDate: Date?
    let calendarEndDate: Date?
    let calendarTitle: String?
    let calendarLocation: String?
    let reminderLeadMinutes: Int?

    init(text: String) {
        let value = text.lowercased()

        let meetingRange = Self.hasCalendarIntent(in: value) ? Self.scheduledRange(in: value) : nil

        if meetingRange != nil && Self.contains(value, ["meeting", "appointment", "calendar event", "video call", "client call", "out of office", "busy"]) {
            category = .work
        } else if Self.contains(value, ["remind me", "remember to", "to-do", "todo", "need to", "want to buy", "to buy", "grocery", "groceries", "shopping list"]) || value.hasPrefix("buy ") {
            category = .list
        } else if Self.contains(value, ["screen time", "used my phone", "on my phone", "social media", "browsing online", "online for"]) {
            category = .screenTime
        } else if Self.contains(value, ["bought", "spent", "paid", "cost", "receipt", "invoice", "total", "€", "$", "£"]) {
            category = .expense
        } else if Self.contains(value, ["slept", "sleep", "nap", "bedtime"]) {
            category = .sleep
        } else if Self.contains(value, ["walk", "run", "gym", "workout", "exercise", "doctor", "medicine", "health"]) {
            category = .fitness
        } else if Self.contains(value, ["breakfast", "lunch", "dinner", "ate", "meal", "coffee", "calories", "protein"]) {
            category = .food
        } else if Self.contains(value, ["book", "read", "chapter", "novel", "author"]) {
            category = .book
        } else if Self.contains(value, ["movie", "film", "cinema", "watch", "series", "episode"]) {
            category = .movie
        } else if Self.contains(value, ["idea", "maybe we could", "build an", "concept"]) {
            category = .idea
        } else if Self.contains(value, ["feel", "felt", "grateful", "anxious", "happy", "sad", "mindset", "meditated"]) {
            category = .mood
        } else if Self.contains(value, ["habit", "routine", "woke", "brush", "shower", "cleaned", "daily"]) {
            category = .routine
        } else if Self.contains(value, ["work", "meeting", "project", "client", "office", "email"]) {
            category = .work
        } else if value.count > 80 || Self.contains(value, ["journal", "today i", "reflection", "dear diary"]) {
            category = .journal
        } else {
            category = .note
        }

        amount = category == .expense ? Self.firstNumber(in: value) : nil
        durationMinutes = Self.duration(in: value)

        if category == .list {
            if Self.contains(value, ["grocery", "groceries", "milk", "bread", "eggs", "vegetable", "fruit", "supermarket"]) {
                listKind = .grocery
            } else if Self.contains(value, ["remind me", "remember to", " at ", "tomorrow", "today"]) {
                listKind = .reminder
            } else if Self.contains(value, ["buy", "purchase", "order", "shopping"]) {
                listKind = .shopping
            } else {
                listKind = .task
            }
            dueDate = Self.reminderDate(in: value)
        } else {
            listKind = nil
            dueDate = nil
        }

        calendarStartDate = meetingRange?.start
        calendarEndDate = meetingRange?.end
        calendarTitle = meetingRange == nil ? nil : Self.calendarTitle(in: text)
        calendarLocation = meetingRange == nil ? nil : Self.calendarLocation(in: text)
        reminderLeadMinutes = meetingRange == nil ? nil : Self.reminderLeadMinutes(in: value)

        if Self.contains(value, ["sleep", "nap", "rest", "bedtime"]) {
            lifeArea = .rest
        } else if category == .work || Self.contains(value, ["client", "office", "meeting", "work project"]) {
            lifeArea = .work
        } else {
            lifeArea = .personal
        }

        if Self.contains(value, ["iphone", "phone", "mobile"]) {
            deviceSource = .phone
        } else if Self.contains(value, ["ipad", "tablet"]) {
            deviceSource = .tablet
        } else if Self.contains(value, ["mac", "laptop", "computer", "desktop"]) {
            deviceSource = .mac
        } else if Self.contains(value, ["web", "online", "browser", "website"]) {
            deviceSource = .web
        } else {
            deviceSource = nil
        }

        if category == .book || category == .movie {
            if Self.contains(value, ["want to", "to watch", "to read", "wishlist", "later"]) {
                status = .planned
            } else if Self.contains(value, ["finished", "completed", "watched", "done", "read it"]) {
                status = .completed
            } else {
                status = .inProgress
            }
        } else {
            status = nil
        }
    }

    private static func contains(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private static func firstNumber(in text: String) -> Double? {
        let pattern = #"\d+(?:[.,]\d{1,2})?"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    private static func duration(in text: String) -> Int? {
        guard contains(text, ["minute", " min", "hour", " hr"]) else { return nil }
        guard let number = firstNumber(in: text) else { return nil }
        if text.contains("hour") || text.contains(" hr") {
            return Int(number * 60)
        }
        return Int(number)
    }

    private static func hasCalendarIntent(in text: String) -> Bool {
        let explicitRequest = contains(text, [
            "add to calendar", "put in calendar", "create an event", "schedule", "book time", "block time"
        ])
        if explicitRequest { return true }

        let retrospective = contains(text, [
            "worked", "i did", "i was", "had a meeting", "added time", "extra time", "last week", "yesterday"
        ])
        if retrospective { return false }

        return contains(text, [
            "meeting", "appointment", "calendar event", "video call", "client call", "out of office", "busy"
        ])
    }

    private static func reminderDate(in text: String, now: Date = .now) -> Date? {
        let hasDateLanguage = contains(text, [" at ", "tomorrow", "today", "remind me", "remember to"])
        guard hasDateLanguage else { return nil }

        let calendar = Calendar.current
        var base = calendar.startOfDay(for: now)
        if text.contains("tomorrow") {
            base = calendar.date(byAdding: .day, value: 1, to: base) ?? base
        }

        let pattern = #"(?:\bat\s+)(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let hourRange = Range(match.range(at: 1), in: text) {
            var hour = Int(text[hourRange]) ?? 9
            var minute = 0
            if match.range(at: 2).location != NSNotFound,
               let minuteRange = Range(match.range(at: 2), in: text) {
                minute = Int(text[minuteRange]) ?? 0
            }
            if match.range(at: 3).location != NSNotFound,
               let periodRange = Range(match.range(at: 3), in: text) {
                let period = text[periodRange]
                if period == "pm", hour < 12 { hour += 12 }
                if period == "am", hour == 12 { hour = 0 }
            }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
        }

        if text.contains("tomorrow") || text.contains("today") {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)
        }
        return nil
    }

    private static func scheduledRange(in text: String, now: Date = .now) -> (start: Date, end: Date)? {
        let schedulingTerms = ["today", "tomorrow", "meeting", "appointment", "calendar event", "video call", "client call", "out of office", "busy"]
            + Calendar.current.weekdaySymbols.map { $0.lowercased() }
        guard contains(text, schedulingTerms) else { return nil }
        let pattern = #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:to|[-–])\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let startHourRange = Range(match.range(at: 1), in: text),
           let endHourRange = Range(match.range(at: 4), in: text) {
            var startHour = Int(text[startHourRange]) ?? 9
            var endHour = Int(text[endHourRange]) ?? (startHour + 1)
            let startMinute = rangeValue(match, index: 2, text: text) ?? 0
            let endMinute = rangeValue(match, index: 5, text: text) ?? 0
            let startPeriod = rangeText(match, index: 3, text: text)
            let endPeriod = rangeText(match, index: 6, text: text)
            startHour = normalizedHour(startHour, period: startPeriod ?? endPeriod)
            endHour = normalizedHour(endHour, period: endPeriod ?? startPeriod)
            return datesForSchedule(
                text: text,
                now: now,
                startHour: startHour,
                startMinute: startMinute,
                endHour: endHour,
                endMinute: endMinute
            )
        }

        guard contains(text, ["tomorrow", "today"] + Calendar.current.weekdaySymbols.map { $0.lowercased() }) else { return nil }
        let singlePattern = #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        guard let expression = try? NSRegularExpression(pattern: singlePattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text) else { return nil }
        let hour = normalizedHour(Int(text[hourRange]) ?? 9, period: rangeText(match, index: 3, text: text))
        let minute = rangeValue(match, index: 2, text: text) ?? 0
        guard let values = datesForSchedule(
            text: text,
            now: now,
            startHour: hour,
            startMinute: minute,
            endHour: hour,
            endMinute: minute
        ) else { return nil }
        let minutes = duration(in: text) ?? 60
        return (values.start, values.start.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    private static func calendarTitle(in text: String) -> String {
        let lowered = text.lowercased()
        guard let meetingRange = lowered.range(of: #"\b(meeting|appointment|video call|client call)\b"#, options: .regularExpression) else {
            return "Calendar event"
        }
        let kind = lowered[meetingRange].contains("appointment") ? "Appointment" : lowered[meetingRange].contains("call") ? "Call" : "Meeting"
        let tail = String(text[meetingRange.upperBound...])
        if let withRange = tail.range(of: #"\bwith\s+(.+?)(?=\s+(?:at|in|today|tomorrow|from|remind)\b|$)"#, options: [.regularExpression, .caseInsensitive]) {
            let person = tail[withRange]
                .replacingOccurrences(of: #"^with\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !person.isEmpty { return "\(kind) with \(person)" }
        }
        return kind
    }

    private static func calendarLocation(in text: String) -> String? {
        let lowered = text.lowercased()
        guard let meetingRange = lowered.range(of: #"\b(meeting|appointment|video call|client call)\b"#, options: .regularExpression) else { return nil }
        let tail = String(text[meetingRange.upperBound...])
        guard let range = tail.range(
            of: #"\b(?:at|in)\s+(.+?)(?=\s+(?:from|remind(?:er)?|with an alert)\b|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let location = tail[range]
            .replacingOccurrences(of: #"^(?:at|in)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return location.isEmpty ? nil : location
    }

    private static func datesForSchedule(
        text: String,
        now: Date,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int
    ) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: now)
        if text.contains("tomorrow") {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        } else if !text.contains("today"),
                  let weekday = weekdayOffset(in: text, from: now, calendar: calendar) {
            day = calendar.date(byAdding: .day, value: weekday, to: day) ?? day
        }
        guard let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day),
              var end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: day) else { return nil }
        if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return (start, end)
    }

    private static func reminderLeadMinutes(in text: String) -> Int? {
        guard text.contains("remind") || text.contains("reminder") || text.contains("alert") else { return nil }
        let pattern = #"(\d+)\s*(minute|min|hour|hr|day)s?\s*before"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let numberRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text) {
            let number = Int(text[numberRange]) ?? 15
            let unit = String(text[unitRange])
            if unit.hasPrefix("day") { return number * 1_440 }
            if unit.hasPrefix("hour") || unit == "hr" { return number * 60 }
            return number
        }
        return 15
    }

    private static func normalizedHour(_ hour: Int, period: String?) -> Int {
        guard let period else { return min(max(hour, 0), 23) }
        if period == "pm", hour < 12 { return hour + 12 }
        if period == "am", hour == 12 { return 0 }
        return hour
    }

    private static func rangeValue(_ match: NSTextCheckingResult, index: Int, text: String) -> Int? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    private static func rangeText(_ match: NSTextCheckingResult, index: Int, text: String) -> String? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func weekdayOffset(in text: String, from now: Date, calendar: Calendar) -> Int? {
        let names = calendar.weekdaySymbols.map { $0.lowercased() }
        guard let targetIndex = names.firstIndex(where: { text.contains($0) }) else { return nil }
        let current = calendar.component(.weekday, from: now) - 1
        let delta = (targetIndex - current + 7) % 7
        return delta == 0 ? 7 : delta
    }
}
