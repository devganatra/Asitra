import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AppModel {
    var selectedSection: AppSection? = .today
    var notificationsEnabled = true
    var syncEnabled = false
    var appleRemindersEnabled = UserDefaults.standard.object(forKey: "sakhya.apple-reminders.enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(appleRemindersEnabled, forKey: "sakhya.apple-reminders.enabled")
        }
    }
    private(set) var appleRemindersStatus = "Not connected"
    private(set) var appleRemindersError: String?
    var isImportingFitness = false
    private(set) var lastFitnessImport: Date?
    private(set) var entries: [LogEntry] = []
    private(set) var lists: [SakhyaList] = []

    private let storageKey = "daily-log.entries.v2"
    private let listsStorageKey = "sakhya.lists.v1"
    private let legacyStorageKey = "daily-log.entries.v1"
    private let lastFitnessImportKey = "sakhya.fitness.last-import"
    private let legacyFitnessImportKey = "sakha.fitness.last-import"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: listsStorageKey),
           let savedLists = try? JSONDecoder().decode([SakhyaList].self, from: data),
           !savedLists.isEmpty {
            lists = savedLists
        } else {
            lists = SakhyaList.defaults
        }
        lastFitnessImport = (defaults.object(forKey: lastFitnessImportKey)
            ?? defaults.object(forKey: legacyFitnessImportKey)) as? Date
        let storedData = defaults.data(forKey: storageKey) ?? defaults.data(forKey: legacyStorageKey)
        if let storedData,
           let savedEntries = try? JSONDecoder().decode([LogEntry].self, from: storedData) {
            entries = savedEntries
        } else {
            entries = LogEntry.examples
        }
        migrateListAssignments()
        save()
        appleRemindersStatus = AppleReminderService.shared.statusDescription
    }

    func add(_ entry: LogEntry, photoData: Data? = nil) {
        var storedEntry = entry
        if storedEntry.category == .list, storedEntry.listID == nil {
            storedEntry.listID = defaultList(for: storedEntry.listKind ?? .task)?.id
        }
        if let photoData {
            storedEntry.attachmentFilename = saveAttachment(photoData, id: entry.id)
        }
        entries.append(storedEntry)
        entries.sort { $0.timestamp > $1.timestamp }
        save()
        if storedEntry.category == .list, storedEntry.listKind == .reminder, appleRemindersEnabled {
            syncToAppleReminders(storedEntry)
        } else if storedEntry.category == .list, let dueDate = storedEntry.dueDate {
            scheduleNotification(for: storedEntry, at: dueDate)
        }
    }

    func addCapturedText(_ text: String, on date: Date = .now) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let suggestion = SmartCapture(text: title)
        let destination: SakhyaList?
        if let kind = suggestion.listKind {
            destination = suggestedList(for: title, kind: kind)
        } else {
            destination = nil
        }
        let calendar = Calendar.current
        let timestamp: Date
        if calendar.isDateInToday(date) {
            timestamp = .now
        } else {
            let time = calendar.dateComponents([.hour, .minute], from: .now)
            timestamp = calendar.date(
                bySettingHour: time.hour ?? 12,
                minute: time.minute ?? 0,
                second: 0,
                of: date
            ) ?? date
        }

        add(LogEntry(
            timestamp: timestamp,
            category: suggestion.category,
            title: title,
            amount: suggestion.amount,
            durationMinutes: suggestion.durationMinutes,
            status: suggestion.status,
            lifeArea: suggestion.lifeArea,
            deviceSource: suggestion.deviceSource ?? currentDeviceSource,
            listKind: destination?.kind ?? suggestion.listKind,
            listID: destination?.id,
            dueDate: suggestion.dueDate
        ))
    }

    func defaultList(for kind: ListKind) -> SakhyaList? {
        lists.first { $0.kind == kind && $0.isDefault } ?? lists.first { $0.kind == kind }
    }

    func suggestedList(for text: String, kind: ListKind) -> SakhyaList? {
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

    func list(withID id: UUID?) -> SakhyaList? {
        guard let id else { return nil }
        return lists.first { $0.id == id }
    }

    @discardableResult
    func createList(name: String, kind: ListKind, access: ListAccess) -> UUID {
        let list = SakhyaList(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            access: access
        )
        lists.append(list)
        save()
        return list.id
    }

    func updateList(_ list: SakhyaList) {
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[index] = list
        for entryIndex in entries.indices where entries[entryIndex].listID == list.id {
            entries[entryIndex].listKind = list.kind
        }
        save()
    }

    func deleteList(_ list: SakhyaList) {
        guard !list.isDefault else { return }
        let fallbackID = defaultList(for: list.kind)?.id
        for index in entries.indices where entries[index].listID == list.id {
            entries[index].listID = fallbackID
            entries[index].listKind = list.kind
        }
        lists.removeAll { $0.id == list.id }
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
                    appleRemindersStatus = AppleReminderService.shared.statusDescription
                } catch {
                    appleRemindersError = error.localizedDescription
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
        if let filename = entry.attachmentFilename {
            try? FileManager.default.removeItem(at: attachmentsDirectory.appendingPathComponent(filename))
        }
        entries.removeAll { $0.id == entry.id }
        save()
        if let identifier = entry.appleReminderIdentifier {
            Task {
                do {
                    try AppleReminderService.shared.deleteReminder(identifier: identifier)
                } catch {
                    appleRemindersError = error.localizedDescription
                }
            }
        }
    }

    func connectAppleReminders() async {
        do {
            let granted = try await AppleReminderService.shared.requestAccess()
            appleRemindersStatus = granted ? "Connected" : "Access denied"
            appleRemindersError = granted ? nil : "Enable Reminders access in System Settings."
        } catch {
            appleRemindersStatus = "Connection failed"
            appleRemindersError = error.localizedDescription
        }
    }

    @discardableResult
    func importFitnessData() async throws -> Int {
        isImportingFitness = true
        defer { isImportingFitness = false }

        let imported = try await FitnessImportService.importRecentEntries()
        let knownIdentifiers = Set(entries.compactMap(\.externalIdentifier))
        let newEntries = imported.filter { entry in
            guard let identifier = entry.externalIdentifier else { return true }
            return !knownIdentifiers.contains(identifier)
        }

        entries.append(contentsOf: newEntries)
        entries.sort { $0.timestamp > $1.timestamp }
        lastFitnessImport = .now
        UserDefaults.standard.set(lastFitnessImport, forKey: lastFitnessImportKey)
        save()
        return newEntries.count
    }

    var connectedFitnessSources: [String] {
        Array(Set(entries.compactMap(\.fitnessSource))).sorted()
    }

    private var currentDeviceSource: DeviceSource {
#if os(macOS)
        .mac
#else
        .phone
#endif
    }

    func attachmentData(for entry: LogEntry) -> Data? {
        guard let filename = entry.attachmentFilename else { return nil }
        return try? Data(contentsOf: attachmentsDirectory.appendingPathComponent(filename))
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
        let directory = base.appendingPathComponent("Dayline/Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func saveAttachment(_ data: Data, id: UUID) -> String? {
        let filename = "\(id.uuidString).image"
        do {
            try data.write(to: attachmentsDirectory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        if let data = try? encoder.encode(lists) {
            UserDefaults.standard.set(data, forKey: listsStorageKey)
        }
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
            content.title = entry.listKind?.displayName ?? "Sakhya reminder"
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
                    notes: entry.note.isEmpty ? "Created from Sakhya" : "\(entry.note)\n\nCreated from Sakhya",
                    dueDate: entry.dueDate
                )
                guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
                entries[index].appleReminderIdentifier = identifier
                appleRemindersStatus = "Connected"
                appleRemindersError = nil
                save()
            } catch {
                appleRemindersStatus = "Connection failed"
                appleRemindersError = error.localizedDescription
                if let dueDate = entry.dueDate {
                    scheduleNotification(for: entry, at: dueDate)
                }
            }
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case lists = "Lists"
    case balance = "Balance"
    case collections = "Trackers"
    case insights = "Insights"
    case settings = "Settings"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .today: "clock"
        case .lists: "checklist"
        case .balance: "circle.lefthalf.filled"
        case .collections: "books.vertical"
        case .insights: "chart.bar"
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

struct SakhyaList: Identifiable, Codable, Hashable {
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

    static let defaults: [SakhyaList] = ListKind.allCases.map { kind in
        SakhyaList(name: kind.displayName, kind: kind, isDefault: true)
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
    var lifeArea: LifeArea?
    var deviceSource: DeviceSource?
    var listKind: ListKind?
    var listID: UUID?
    var dueDate: Date?
    var completed: Bool?
    var fitnessSource: String?
    var externalIdentifier: String?
    var appleReminderIdentifier: String?

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

struct SmartCapture {
    let category: LogCategory
    let amount: Double?
    let durationMinutes: Int?
    let status: EntryStatus?
    let lifeArea: LifeArea
    let deviceSource: DeviceSource?
    let listKind: ListKind?
    let dueDate: Date?

    init(text: String) {
        let value = text.lowercased()

        if Self.contains(value, ["remind me", "remember to", "to-do", "todo", "need to", "want to buy", "to buy", "grocery", "groceries", "shopping list"]) || value.hasPrefix("buy ") {
            category = .list
        } else if Self.contains(value, ["screen time", "used my phone", "on my phone", "social media", "browsing online", "online for"]) {
            category = .screenTime
        } else if Self.contains(value, ["bought", "spent", "paid", "cost", "€", "$", "£"]) {
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
}
