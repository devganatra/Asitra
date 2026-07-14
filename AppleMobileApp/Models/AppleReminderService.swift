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

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Apple Reminders access was not granted."
        case .noDefaultList: "Apple Reminders has no default list available."
        case .reminderNotFound: "The linked Apple reminder could not be found."
        }
    }
}
