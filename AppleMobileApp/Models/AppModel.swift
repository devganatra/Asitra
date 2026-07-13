import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var selectedSection: AppSection? = .today
    var notificationsEnabled = true
    var syncEnabled = false
    private(set) var entries: [LogEntry] = []

    private let storageKey = "daily-log.entries.v2"
    private let legacyStorageKey = "daily-log.entries.v1"

    init() {
        let defaults = UserDefaults.standard
        let storedData = defaults.data(forKey: storageKey) ?? defaults.data(forKey: legacyStorageKey)
        if let storedData,
           let savedEntries = try? JSONDecoder().decode([LogEntry].self, from: storedData) {
            entries = savedEntries
        } else {
            entries = LogEntry.examples
        }
        save()
    }

    func add(_ entry: LogEntry, photoData: Data? = nil) {
        var storedEntry = entry
        if let photoData {
            storedEntry.attachmentFilename = saveAttachment(photoData, id: entry.id)
        }
        entries.append(storedEntry)
        entries.sort { $0.timestamp > $1.timestamp }
        save()
    }

    func delete(_ entry: LogEntry) {
        if let filename = entry.attachmentFilename {
            try? FileManager.default.removeItem(at: attachmentsDirectory.appendingPathComponent(filename))
        }
        entries.removeAll { $0.id == entry.id }
        save()
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
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case balance = "Balance"
    case collections = "Collections"
    case insights = "Insights"
    case settings = "Settings"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .today: "clock"
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
    case food = "Food"
    case mood = "Mood"
    case screenTime = "Screen Time"
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
        case .mood: "Mindset"
        case .screenTime: "Screen Time"
        default: rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .routine: "checkmark.circle"
        case .work: "briefcase"
        case .expense: "creditcard"
        case .fitness: "heart.text.square"
        case .food: "fork.knife"
        case .mood: "brain.head.profile"
        case .screenTime: "hourglass"
        case .book: "book.closed"
        case .movie: "film"
        case .journal: "book.pages"
        case .idea: "lightbulb"
        case .note: "text.alignleft"
        }
    }

    var defaultLifeArea: LifeArea {
        self == .work ? .work : .personal
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

    init(text: String) {
        let value = text.lowercased()

        if Self.contains(value, ["screen time", "used my phone", "on my phone", "social media", "browsing online", "online for"]) {
            category = .screenTime
        } else if Self.contains(value, ["bought", "spent", "paid", "cost", "€", "$", "£"]) {
            category = .expense
        } else if Self.contains(value, ["walk", "run", "gym", "workout", "exercise", "sleep", "doctor", "medicine", "health"]) {
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
}
