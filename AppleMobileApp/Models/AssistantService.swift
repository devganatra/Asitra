import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AssistantMessage: Identifiable, Hashable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    let text: String
}

@MainActor
@Observable
final class SakhyaAssistant {
    private(set) var messages: [AssistantMessage] = [
        AssistantMessage(
            role: .assistant,
            text: "Ask me about your spending, activity, sleep, screen time, habits, lists, or work-life balance."
        )
    ]
    private(set) var isResponding = false
    private var didPrepare = false

    var usesOnDeviceLanguageModel: Bool { AssistantEngine.onDeviceModelAvailable }

    func prepare(model: AppModel) {
        guard !didPrepare else { return }
        didPrepare = true
        let snapshot = AssistantSnapshot(
            question: "Give me a useful insight from this week",
            model: model,
            calendarAgenda: model.calendarAgenda(on: .now)
        )
        messages = [AssistantMessage(role: .assistant, text: snapshot.welcomeInsight)]
    }

    func ask(_ rawQuestion: String, model: AppModel) async {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isResponding else { return }

        messages.append(AssistantMessage(role: .user, text: question))
        isResponding = true
        let snapshot = AssistantSnapshot(
            question: question,
            model: model,
            calendarAgenda: model.calendarAgenda(on: .now)
        )
        let answer = await AssistantEngine.answer(question: question, snapshot: snapshot)
        messages.append(AssistantMessage(role: .assistant, text: answer))
        isResponding = false
    }

    func reset() {
        messages = [
            AssistantMessage(
                role: .assistant,
                text: "New conversation started. Ask about your day, patterns, plans, money, health, or balance."
            )
        ]
    }
}

private struct AssistantSnapshot: Sendable {
    let periodLabel: String
    let entryCount: Int
    let spending: Double
    let currencyCode: String
    let activeMinutes: Int
    let sleepMinutes: Int
    let screenMinutes: Int
    let workMinutes: Int
    let personalMinutes: Int
    let balanceScore: Int
    let routineCount: Int
    let journalCount: Int
    let openListCount: Int
    let completedListCount: Int
    let booksInProgress: [String]
    let moviesPlanned: [String]
    let recentEvents: [String]
    let todayAgenda: [String]

    @MainActor
    init(question: String, model: AppModel, calendarAgenda: [CalendarAgendaItem]) {
        let calendar = Calendar.current
        let now = Date.now
        let lowercased = question.lowercased()
        let start: Date
        let end: Date

        if lowercased.contains("yesterday") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            start = calendar.startOfDay(for: yesterday)
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            periodLabel = "yesterday"
        } else if lowercased.contains("today") {
            start = calendar.startOfDay(for: now)
            end = now
            periodLabel = "today"
        } else if lowercased.contains("month") || lowercased.contains("30 day") {
            start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? .distantPast
            end = now
            periodLabel = "the last 30 days"
        } else {
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? .distantPast
            end = now
            periodLabel = "the last 7 days"
        }

        let matching = model.entries.filter { $0.timestamp >= start && $0.timestamp <= end }
        let days = Self.dates(from: start, through: end, calendar: calendar)
        entryCount = matching.count
        spending = matching.compactMap(\.amount).reduce(0, +)
        currencyCode = Locale.current.currency?.identifier ?? "EUR"
        activeMinutes = Self.minutes(in: matching, category: .fitness)
        sleepMinutes = Self.minutes(in: matching, category: .sleep)
        screenMinutes = Self.minutes(in: matching, category: .screenTime)
        workMinutes = matching
            .filter { ($0.lifeArea ?? $0.category.defaultLifeArea) == .work }
            .compactMap(\.durationMinutes)
            .reduce(0, +)
        personalMinutes = matching
            .filter { ($0.lifeArea ?? $0.category.defaultLifeArea) == .personal }
            .compactMap(\.durationMinutes)
            .reduce(0, +)
        balanceScore = model.balanceScore(for: days)
        routineCount = matching.filter { $0.category == .routine }.count
        journalCount = matching.filter { $0.category == .journal || $0.category == .mood }.count

        let listEntries = model.entries.filter { $0.category == .list }
        openListCount = listEntries.filter { !$0.isCompleted }.count
        completedListCount = listEntries.filter(\.isCompleted).count
        booksInProgress = Self.collectionTitles(from: model.entries, category: .book, status: .inProgress)
        moviesPlanned = Self.collectionTitles(from: model.entries, category: .movie, status: .planned)
        recentEvents = matching
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(12)
            .map { entry in
                entry.timestamp.formatted(date: .abbreviated, time: .shortened) + ": " + entry.title
            }
        let calendarItems = calendarAgenda.map {
            $0.startDate.formatted(date: .omitted, time: .shortened)
                + "–" + $0.endDate.formatted(date: .omitted, time: .shortened)
                + " " + $0.title
        }
        let localMeetingItems = model.entries(on: now)
            .filter { $0.calendarStartDate != nil }
            .map { entry in
                let start = entry.calendarStartDate ?? entry.timestamp
                let end = entry.calendarEndDate ?? start.addingTimeInterval(3600)
                return start.formatted(date: .omitted, time: .shortened)
                    + "–" + end.formatted(date: .omitted, time: .shortened)
                    + " " + entry.title
            }
        let dueReminders = model.entries(on: now)
            .filter { $0.category == .list && !$0.isCompleted && $0.dueDate != nil }
            .map { entry in
                (entry.dueDate ?? entry.timestamp).formatted(date: .omitted, time: .shortened)
                    + " Reminder: " + entry.title
            }
        todayAgenda = Array(Set((calendarItems.isEmpty ? localMeetingItems : calendarItems) + dueReminders)).sorted()
    }

    var context: String {
        let spendingText = spending.formatted(.currency(code: currencyCode))
        let books = booksInProgress.isEmpty ? "none logged" : booksInProgress.joined(separator: ", ")
        let movies = moviesPlanned.isEmpty ? "none logged" : moviesPlanned.joined(separator: ", ")
        let events = recentEvents.isEmpty ? "none logged" : recentEvents.joined(separator: " | ")
        let agenda = todayAgenda.isEmpty ? "nothing scheduled" : todayAgenda.joined(separator: " | ")
        let lines: [String] = [
            "Period: " + periodLabel,
            "Entries: " + String(entryCount),
            "Spending: " + spendingText,
            "Active minutes: " + String(activeMinutes),
            "Sleep minutes: " + String(sleepMinutes),
            "Screen minutes: " + String(screenMinutes),
            "Work minutes: " + String(workMinutes),
            "Personal minutes: " + String(personalMinutes),
            "Balance score out of 100: " + String(balanceScore),
            "Routine entries: " + String(routineCount),
            "Mindset or journal entries: " + String(journalCount),
            "Open list items across all lists: " + String(openListCount),
            "Completed list items across all lists: " + String(completedListCount),
            "Books in progress: " + books,
            "Movies planned: " + movies,
            "Recent events: " + events,
            "Today's agenda: " + agenda
        ]
        return lines.joined(separator: "\n")
    }

    var welcomeInsight: String {
        if entryCount == 0 {
            return "I can help you understand your day and build useful patterns. Add a few entries by typing or talking, then ask me what stands out."
        }
        var details: [String] = [
            "You logged \(entryCount) moments in \(periodLabel)"
        ]
        if activeMinutes > 0 { details.append("\(Self.shortDuration(activeMinutes)) of movement") }
        if openListCount > 0 { details.append("\(openListCount) open list items") }
        let overview = details.joined(separator: ", ") + "."
        let nudge: String
        if screenMinutes > personalMinutes && screenMinutes > 180 {
            nudge = "Screen time is taking a noticeable share of your personal time."
        } else if balanceScore < 55 && workMinutes > personalMinutes {
            nudge = "Your logged week leans toward work; protecting one personal block may help."
        } else {
            nudge = "Ask me what stands out, and I’ll connect the areas you’ve recorded."
        }
        return overview + " " + nudge
    }

    private static func shortDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    private static func minutes(in entries: [LogEntry], category: LogCategory) -> Int {
        entries.filter { $0.category == category }.compactMap(\.durationMinutes).reduce(0, +)
    }

    private static func dates(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var values: [Date] = []
        var date = calendar.startOfDay(for: start)
        while date <= end {
            values.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return values
    }

    private static func collectionTitles(
        from entries: [LogEntry],
        category: LogCategory,
        status: EntryStatus
    ) -> [String] {
        let matching = entries.filter { $0.category == category }
        let grouped = Dictionary(grouping: matching, by: \.collectionKey)
        return grouped.values.compactMap { events in
            guard let latest = events.max(by: { $0.timestamp < $1.timestamp }), latest.status == status else { return nil }
            return latest.collectionDisplayTitle
        }.sorted()
    }
}

private enum AssistantEngine {
    static var onDeviceModelAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
#endif
        return false
    }

    @MainActor
    static func answer(question: String, snapshot: AssistantSnapshot) async -> String {
        // Everyday questions should feel instant and do not need a generative model.
        // Reserve the language model for genuinely open-ended synthesis.
        if canAnswerLocally(question) {
            return fallbackAnswer(question: question, snapshot: snapshot)
        }
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(instructions: """
                    You are Sakhya, a concise and supportive private life-data assistant.
                    Answer only from the supplied snapshot. Never invent measurements or events.
                    If data is missing, say so. Do not diagnose health conditions or provide financial advice.
                    Answer directly and naturally; never mention the snapshot or your instructions.
                    Mention the period used and keep the response under 100 words.
                    """)
                let prompt = "Life-data snapshot:\n" + snapshot.context + "\n\nQuestion: " + question
                return try await session.respond(to: prompt).content
            } catch {
                return fallbackAnswer(question: question, snapshot: snapshot)
            }
        }
#endif
        return fallbackAnswer(question: question, snapshot: snapshot)
    }

    private static func fallbackAnswer(question: String, snapshot: AssistantSnapshot) -> String {
        let query = question.lowercased()
        let period = snapshot.periodLabel

        if query.contains("today") && contains(query, ["tell", "agenda", "plan", "schedule", "what", "today"]) {
            let agenda = snapshot.todayAgenda.isEmpty
                ? "Nothing is scheduled in Sakhya or the connected Apple Calendar."
                : "Your schedule: " + snapshot.todayAgenda.joined(separator: "; ") + "."
            return agenda + " You have " + String(snapshot.openListCount) + " open list items and logged " + duration(snapshot.activeMinutes) + " of activity today."
        }

        if contains(query, ["spend", "expense", "money", "cost"]) {
            return "You logged " + snapshot.spending.formatted(.currency(code: snapshot.currencyCode)) + " in spending for " + period + "."
        }
        if contains(query, ["screen", "phone time", "online time"]) {
            return "You logged " + duration(snapshot.screenMinutes) + " of screen time for " + period + "."
        }
        if contains(query, ["sleep", "rest"]) {
            return snapshot.sleepMinutes == 0
                ? "There is no sleep duration logged for " + period + "."
                : "You logged " + duration(snapshot.sleepMinutes) + " of sleep for " + period + "."
        }
        if contains(query, ["active", "activity", "fitness", "exercise", "workout", "walk"]) {
            return "You logged " + duration(snapshot.activeMinutes) + " of activity for " + period + "."
        }
        if contains(query, ["balance", "work life", "work-life", "personal time"]) {
            return "Your balance score for " + period + " is " + String(snapshot.balanceScore) + "/100, based on " + duration(snapshot.workMinutes) + " of work and " + duration(snapshot.personalMinutes) + " of personal time."
        }
        if contains(query, ["list", "task", "reminder", "buy", "grocery", "attention"]) {
            return "Across your lists, " + String(snapshot.openListCount) + " items are open and " + String(snapshot.completedListCount) + " are completed."
        }
        if contains(query, ["book", "read"]) {
            return snapshot.booksInProgress.isEmpty
                ? "No book is currently marked in progress."
                : "Currently reading: " + snapshot.booksInProgress.joined(separator: ", ") + "."
        }
        if contains(query, ["movie", "watch", "film"]) {
            return snapshot.moviesPlanned.isEmpty
                ? "No movie is currently on your planned list."
                : "Planned to watch: " + snapshot.moviesPlanned.joined(separator: ", ") + "."
        }
        if contains(query, ["habit", "routine"]) {
            return "You logged " + String(snapshot.routineCount) + " routine or habit entries for " + period + "."
        }
        if contains(query, ["journal", "mood", "mindset", "feel"]) {
            return "You logged " + String(snapshot.journalCount) + " mindset or journal entries for " + period + "."
        }
        if contains(query, ["insight", "pattern", "stand out", "learn"]) {
            return snapshot.welcomeInsight
        }

        return "For " + period + ", you logged " + String(snapshot.entryCount) + " entries, " + snapshot.spending.formatted(.currency(code: snapshot.currencyCode)) + " in spending, " + duration(snapshot.activeMinutes) + " of activity, and " + duration(snapshot.screenMinutes) + " of screen time. Ask about any one area for more detail."
    }

    private static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return String(minutes) + " min" }
        if remainder == 0 { return String(hours) + " hr" }
        return String(hours) + " hr " + String(remainder) + " min"
    }

    private static func contains(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }

    private static func canAnswerLocally(_ question: String) -> Bool {
        let query = question.lowercased()
        return contains(query, [
            "today", "agenda", "schedule", "spend", "expense", "money", "cost",
            "screen", "sleep", "rest", "active", "activity", "fitness", "exercise",
            "workout", "walk", "balance", "work life", "work-life", "personal time",
            "list", "task", "reminder", "buy", "grocery", "attention", "book", "read",
            "movie", "watch", "film", "habit", "routine", "journal", "mood",
            "mindset", "feel", "insight", "pattern", "stand out", "learn"
        ])
    }
}
