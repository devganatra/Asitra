import Foundation
import SakhyaContracts
import SwiftData

@MainActor
struct AppEnvironment {
    let container: ModelContainer
    let timelineRepository: SwiftDataTimelineRepository
    let listRepository: SwiftDataListRepository
    let calendarRepository: CalendarRepository
    let healthRepository: HealthRepository
    let sharedListRepository: SharedListRepository
    let systemRepository: SystemRepository
    let todaySystemEngine: TodaySystemEngine
    let aiProvider: AIProvider
    let wearableProviders: [WearableProvider]
    let captureEntry: CaptureTimelineEntryUseCase
    let importHealth: ImportHealthEntriesUseCase

    static func live(container: ModelContainer) -> AppEnvironment {
        AppEnvironment(
            container: container,
            timelineRepository: SwiftDataTimelineRepository(container: container),
            listRepository: SwiftDataListRepository(container: container),
            calendarRepository: AppleCalendarRepository(),
            healthRepository: AppleHealthRepository(),
            sharedListRepository: CloudKitSharedListRepository(),
            systemRepository: SwiftDataSystemRepository(container: container),
            todaySystemEngine: TodaySystemEngine(),
            aiProvider: OnDeviceCaptureAIProvider(),
            wearableProviders: [],
            captureEntry: CaptureTimelineEntryUseCase(),
            importHealth: ImportHealthEntriesUseCase()
        )
    }
}

struct CaptureTimelineEntryUseCase {
    func makeEntry(
        text: String,
        selectedDate: Date,
        destination: SakhyaList?,
        deviceSource: DeviceSource,
        captureNote: String,
        calendarOverride: CalendarCaptureOverride?
    ) -> LogEntry? {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let suggestion = SmartCapture(text: title)
        let calendar = Calendar.current
        let timestamp: Date
        if let meetingStart = calendarOverride?.startDate ?? suggestion.calendarStartDate {
            timestamp = meetingStart
        } else if calendar.isDateInToday(selectedDate) {
            timestamp = .now
        } else {
            let time = calendar.dateComponents([.hour, .minute], from: .now)
            timestamp = calendar.date(
                bySettingHour: time.hour ?? 12,
                minute: time.minute ?? 0,
                second: 0,
                of: selectedDate
            ) ?? selectedDate
        }

        return LogEntry(
            timestamp: timestamp,
            category: suggestion.category,
            title: title,
            note: captureNote,
            amount: suggestion.amount,
            durationMinutes: suggestion.durationMinutes,
            status: suggestion.status,
            lifeArea: suggestion.lifeArea,
            deviceSource: suggestion.deviceSource ?? deviceSource,
            listKind: destination?.kind ?? suggestion.listKind,
            listID: destination?.id,
            dueDate: suggestion.dueDate,
            calendarStartDate: calendarOverride?.startDate ?? suggestion.calendarStartDate,
            calendarEndDate: calendarOverride?.endDate ?? suggestion.calendarEndDate,
            calendarTitle: calendarOverride?.title ?? suggestion.calendarTitle,
            calendarLocation: calendarOverride?.location ?? suggestion.calendarLocation,
            reminderLeadMinutes: calendarOverride?.reminderLeadMinutes ?? suggestion.reminderLeadMinutes
        )
    }
}

struct ImportHealthEntriesUseCase {
    func newEntries(from imported: [LogEntry], existing: [LogEntry]) -> [LogEntry] {
        let knownIdentifiers = Set(existing.compactMap(\.externalIdentifier))
        return imported.filter { entry in
            guard let identifier = entry.externalIdentifier else { return true }
            return !knownIdentifiers.contains(identifier)
        }
    }
}
