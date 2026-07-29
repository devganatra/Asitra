import AuthenticationServices
import Foundation
import Observation

struct AssistantMessage: Identifiable, Hashable {
    enum Role: String, Hashable { case user, assistant }

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
    let account = SakhyaAIAccount.shared

    var usesTerra: Bool { account.isConnected }
    var serviceLabel: String { account.isConnected ? "Private · Terra" : "Private · Offline insights" }

    func prepare(model: AppModel, finance: FinanceWorkspace) {
        guard !didPrepare else { return }
        didPrepare = true
        let snapshot = AssistantSnapshot(
            question: "Give me a useful insight from this week",
            model: model,
            finance: finance,
            calendarAgenda: model.calendarAgenda(on: .now)
        )
        messages = [AssistantMessage(role: .assistant, text: snapshot.welcomeInsight)]
    }

    func ask(_ rawQuestion: String, model: AppModel, finance: FinanceWorkspace) async {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isResponding else { return }

        messages.append(AssistantMessage(role: .user, text: question))
        isResponding = true
        let snapshot = AssistantSnapshot(
            question: question,
            model: model,
            finance: finance,
            calendarAgenda: model.calendarAgenda(on: .now)
        )
        let answer = await AssistantEngine.answer(
            question: question,
            conversation: Array(messages.suffix(12)),
            snapshot: snapshot,
            sessionToken: account.sessionToken
        )
        messages.append(AssistantMessage(role: .assistant, text: answer))
        isResponding = false
    }

    func completeAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        await account.completeAppleAuthorization(result)
        if account.isConnected {
            messages.append(
                AssistantMessage(
                    role: .assistant,
                    text: "Terra is connected. I’ll use the same Sakhya model as the web app while keeping calculations grounded in your saved data."
                )
            )
        }
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
    let activitySources: [String]
    let sleepSources: [String]
    let spendingSources: [String]
    let income: Double
    let saved: Double
    let invested: Double
    let assets: Double
    let liabilities: Double
    let netWorth: Double
    let unallocatedSurplus: Double

    @MainActor
    init(
        question: String,
        model: AppModel,
        finance: FinanceWorkspace,
        calendarAgenda: [CalendarAgendaItem]
    ) {
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
        activitySources = Self.sources(
            matching.filter { $0.category == .fitness }.compactMap(\.fitnessSource),
            fallback: "Sakhya timeline"
        )
        sleepSources = Self.sources(
            matching.filter { $0.category == .sleep }.compactMap(\.fitnessSource),
            fallback: "Sakhya timeline"
        )
        spendingSources = Self.sources(
            matching.filter { $0.category == .expense }.compactMap { entry in
                entry.financialInstitutionName ?? entry.fitnessSource
            },
            fallback: "Sakhya timeline"
        )
        income = finance.moneyEntries
            .filter { $0.kind == .income && $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + $1.amount }
        invested = finance.moneyEntries
            .filter { $0.kind == .investment && $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + $1.amount }
        saved = finance.savingPlans
            .flatMap(\.contributions)
            .filter { $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + $1.amount }
        assets = finance.balanceSheetItems
            .filter(\.category.isAsset)
            .reduce(0) { $0 + $1.balance }
        liabilities = finance.balanceSheetItems
            .filter { !$0.category.isAsset }
            .reduce(0) { $0 + $1.balance }
        netWorth = assets - liabilities
        unallocatedSurplus = income - spending - saved - invested

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
            "Income: " + income.formatted(.currency(code: currencyCode)),
            "Saved: " + saved.formatted(.currency(code: currencyCode)),
            "Invested: " + invested.formatted(.currency(code: currencyCode)),
            "Net worth: " + netWorth.formatted(.currency(code: currencyCode)),
            "Unallocated surplus: " + unallocatedSurplus.formatted(.currency(code: currencyCode)),
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

    private static func sources(_ values: [String], fallback: String) -> [String] {
        let unique = Array(Set(values.filter { !$0.isEmpty })).sorted()
        return unique.isEmpty ? [fallback] : unique
    }

    var remoteContext: RemoteAssistantContext {
        RemoteAssistantContext(
            generatedAt: ISO8601DateFormatter().string(from: .now),
            timezone: TimeZone.current.identifier,
            verifiedMetrics: [
                RemoteGroundedMetric(
                    name: "spending",
                    value: spending,
                    unit: currencyCode,
                    period: periodLabel,
                    source: spendingSources.joined(separator: ", ")
                ),
                RemoteGroundedMetric(
                    name: "movement",
                    value: Double(activeMinutes),
                    unit: "minutes",
                    period: periodLabel,
                    source: activitySources.joined(separator: ", ")
                ),
                RemoteGroundedMetric(
                    name: "sleep",
                    value: Double(sleepMinutes),
                    unit: "minutes",
                    period: periodLabel,
                    source: sleepSources.joined(separator: ", ")
                ),
                RemoteGroundedMetric(
                    name: "screen time",
                    value: Double(screenMinutes),
                    unit: "minutes",
                    period: periodLabel,
                    source: "Sakhya timeline"
                ),
                RemoteGroundedMetric(
                    name: "work time",
                    value: Double(workMinutes),
                    unit: "minutes",
                    period: periodLabel,
                    source: "Sakhya timeline"
                ),
                RemoteGroundedMetric(
                    name: "personal time",
                    value: Double(personalMinutes),
                    unit: "minutes",
                    period: periodLabel,
                    source: "Sakhya timeline"
                ),
                RemoteGroundedMetric(
                    name: "work-life balance score",
                    value: Double(balanceScore),
                    unit: "out of 100",
                    period: periodLabel,
                    source: "Sakhya balance engine"
                )
            ],
            entries: recentEvents.map(RemoteContextEntry.init(summary:)),
            lists: [
                RemoteContextList(name: "Open items", count: openListCount),
                RemoteContextList(name: "Completed items", count: completedListCount)
            ],
            trackers: [
                RemoteContextTracker(name: "Routine check-ins", count: routineCount),
                RemoteContextTracker(name: "Mindset and journal check-ins", count: journalCount)
            ],
            money: RemoteMoneyContext(
                currency: currencyCode,
                spending: spending,
                income: income,
                saved: saved,
                invested: invested,
                assets: assets,
                liabilities: liabilities,
                netWorth: netWorth,
                unallocatedSurplus: unallocatedSurplus,
                period: periodLabel
            ),
            agenda: todayAgenda
        )
    }
}

private enum AssistantEngine {
    @MainActor
    static func answer(
        question: String,
        conversation: [AssistantMessage],
        snapshot: AssistantSnapshot,
        sessionToken: String?
    ) async -> String {
        if let sessionToken {
            do {
                return try await RemoteTerraAssistant.answer(
                    conversation: conversation,
                    context: snapshot.remoteContext,
                    sessionToken: sessionToken
                )
            } catch {
                return fallbackAnswer(question: question, snapshot: snapshot)
                    + "\n\nTerra could not be reached, so this answer was calculated privately on this device."
            }
        }
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
            return "For " + period + ", you recorded "
                + snapshot.income.formatted(.currency(code: snapshot.currencyCode))
                + " of income and "
                + snapshot.spending.formatted(.currency(code: snapshot.currencyCode))
                + " of spending. Recorded net worth is "
                + snapshot.netWorth.formatted(.currency(code: snapshot.currencyCode))
                + "."
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

}

private enum RemoteTerraAssistant {
    private static let endpoint = URL(
        string: "https://sakhya-everyday.deepanddev.chatgpt.site/api/native/assistant"
    )!

    static func answer(
        conversation: [AssistantMessage],
        context: RemoteAssistantContext,
        sessionToken: String
    ) async throws -> String {
        let body = RemoteAssistantRequest(
            messages: conversation.map {
                RemoteAssistantMessage(
                    role: $0.role == .user ? "user" : "assistant",
                    text: $0.text
                )
            },
            context: context
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RemoteAssistantError.invalidResponse
        }
        let result = try JSONDecoder().decode(RemoteAssistantResponse.self, from: data)
        guard !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteAssistantError.invalidResponse
        }
        return result.answer
    }
}

private struct RemoteAssistantRequest: Encodable {
    let messages: [RemoteAssistantMessage]
    let context: RemoteAssistantContext
}

private struct RemoteAssistantMessage: Encodable {
    let role: String
    let text: String
}

private struct RemoteAssistantResponse: Decodable {
    let answer: String
}

private struct RemoteAssistantContext: Encodable {
    let generatedAt: String
    let timezone: String
    let verifiedMetrics: [RemoteGroundedMetric]
    let entries: [RemoteContextEntry]
    let lists: [RemoteContextList]
    let trackers: [RemoteContextTracker]
    let money: RemoteMoneyContext
    let agenda: [String]
}

private struct RemoteGroundedMetric: Encodable {
    let name: String
    let value: Double
    let unit: String
    let period: String
    let source: String
}

private struct RemoteContextEntry: Encodable {
    let summary: String
}

private struct RemoteContextList: Encodable {
    let name: String
    let count: Int
}

private struct RemoteContextTracker: Encodable {
    let name: String
    let count: Int
}

private struct RemoteMoneyContext: Encodable {
    let currency: String
    let spending: Double
    let income: Double
    let saved: Double
    let invested: Double
    let assets: Double
    let liabilities: Double
    let netWorth: Double
    let unallocatedSurplus: Double
    let period: String
}

private enum RemoteAssistantError: Error {
    case invalidResponse
}
