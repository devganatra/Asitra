import Foundation
import Observation

@MainActor
@Observable
final class TimelineFeatureModel {
    var entries: [LogEntry]
    var recentlyDeleted: [DeletedEntry]
    private let repository: TimelineRepository

    init(repository: TimelineRepository, entries: [LogEntry] = [], recentlyDeleted: [DeletedEntry] = []) {
        self.repository = repository
        self.entries = entries
        self.recentlyDeleted = recentlyDeleted
    }

    func load() throws {
        entries = try repository.loadEntries()
        recentlyDeleted = try repository.loadRecentlyDeleted()
    }

    func persist() throws {
        try repository.save(entries: entries, recentlyDeleted: recentlyDeleted)
    }
}

@MainActor
@Observable
final class CalendarFeatureModel {
    var remindersEnabled: Bool
    var calendarEnabled: Bool
    private(set) var remindersStatus: String
    private(set) var calendarStatus: String
    private(set) var errorMessage: String?

    init(defaults: UserDefaults = .standard) {
        remindersEnabled = defaults.object(forKey: "sakhya.apple-reminders.enabled") as? Bool ?? true
        calendarEnabled = defaults.object(forKey: "sakhya.apple-calendar.enabled") as? Bool ?? true
        remindersStatus = AppleReminderService.shared.statusDescription
        calendarStatus = AppleReminderService.shared.calendarStatusDescription
    }

    func setRemindersEnabled(_ enabled: Bool) {
        remindersEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "sakhya.apple-reminders.enabled")
    }

    func setCalendarEnabled(_ enabled: Bool) {
        calendarEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "sakhya.apple-calendar.enabled")
    }

    func update(remindersStatus: String? = nil, calendarStatus: String? = nil) {
        if let remindersStatus { self.remindersStatus = remindersStatus }
        if let calendarStatus { self.calendarStatus = calendarStatus }
    }

    func setError(_ error: String?) { errorMessage = error }
}

@MainActor
@Observable
final class HealthFeatureModel {
    var isImporting = false
    private(set) var lastImport: Date?

    init(defaults: UserDefaults = .standard) {
        lastImport = (defaults.object(forKey: "sakhya.fitness.last-import")
            ?? defaults.object(forKey: "sakha.fitness.last-import")) as? Date
    }

    func beginImport() { isImporting = true }

    func finishImport(at date: Date? = nil) {
        isImporting = false
        if let date {
            lastImport = date
            UserDefaults.standard.set(date, forKey: "sakhya.fitness.last-import")
        }
    }
}

@MainActor
protocol CalendarRepository {
    func agenda(on date: Date) -> [CalendarAgendaItem]
    func requestCalendarAccess() async throws -> Bool
    func requestReminderAccess() async throws -> Bool
}

@MainActor
struct AppleCalendarRepository: CalendarRepository {
    func agenda(on date: Date) -> [CalendarAgendaItem] {
        AppleReminderService.shared.calendarAgenda(on: date)
    }

    func requestCalendarAccess() async throws -> Bool {
        try await AppleReminderService.shared.requestCalendarAccess()
    }

    func requestReminderAccess() async throws -> Bool {
        try await AppleReminderService.shared.requestAccess()
    }
}

protocol HealthRepository {
    func importRecentEntries() async throws -> [LogEntry]
}

struct AppleHealthRepository: HealthRepository {
    func importRecentEntries() async throws -> [LogEntry] {
        try await FitnessImportService.importRecentEntries()
    }
}
