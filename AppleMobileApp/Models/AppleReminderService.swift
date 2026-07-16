import EventKit
import Foundation

@MainActor
final class AppleReminderService {
    static let shared = AppleReminderService()

    private let store = EKEventStore()

    var statusDescription: String {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: "Connected"
        case .denied, .restricted: "Access denied"
        case .notDetermined: "Not connected"
        case .writeOnly: "Write-only access"
        @unknown default: "Unknown"
        }
    }

    var calendarStatusDescription: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: "Connected"
        case .writeOnly: "Write-only access"
        case .denied, .restricted: "Access denied"
        case .notDetermined: "Not connected"
        @unknown default: "Unknown"
        }
    }

    func requestAccess() async throws -> Bool {
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            return true
        }

        return try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func createReminder(title: String, notes: String, dueDate: Date?) async throws -> String {
        guard try await requestAccess() else { throw AppleReminderError.accessDenied }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw AppleReminderError.noDefaultList
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func requestCalendarAccess() async throws -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    func createCalendarEvent(
        title: String,
        location: String?,
        notes: String,
        startDate: Date,
        endDate: Date,
        reminderLeadMinutes: Int?
    ) async throws -> String {
        guard try await requestCalendarAccess() else { throw AppleReminderError.calendarAccessDenied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw AppleReminderError.noDefaultCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.location = location
        event.notes = notes
        event.startDate = startDate
        event.endDate = max(endDate, startDate.addingTimeInterval(60))
        if let minutes = reminderLeadMinutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
        }
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    func calendarAgenda(on date: Date) -> [CalendarAgendaItem] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { CalendarAgendaItem(title: $0.title ?? "Untitled event", startDate: $0.startDate, endDate: $0.endDate) }
            .sorted { $0.startDate < $1.startDate }
    }

    func deleteCalendarEvent(identifier: String) throws {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func setCompleted(_ completed: Bool, identifier: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw AppleReminderError.reminderNotFound
        }
        reminder.isCompleted = completed
        reminder.completionDate = completed ? .now : nil
        try store.save(reminder, commit: true)
    }

    func deleteReminder(identifier: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }
}

enum AppleReminderError: LocalizedError {
    case accessDenied
    case noDefaultList
    case reminderNotFound
    case calendarAccessDenied
    case noDefaultCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Apple Reminders access was not granted."
        case .noDefaultList: "Apple Reminders has no default list available."
        case .reminderNotFound: "The linked Apple reminder could not be found."
        case .calendarAccessDenied: "Apple Calendar access was not granted."
        case .noDefaultCalendar: "Apple Calendar has no default writable calendar."
        }
    }
}

struct CalendarAgendaItem: Sendable, Hashable {
    let title: String
    let startDate: Date
    let endDate: Date
}
