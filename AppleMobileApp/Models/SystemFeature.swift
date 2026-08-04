import Foundation
import Observation
import SwiftData

enum SystemCadence: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"

    var id: Self { self }
}

enum ActionEnergy: String, Codable, CaseIterable, Identifiable {
    case low = "Low energy"
    case medium = "Medium energy"
    case high = "High energy"

    var id: Self { self }
}

enum TaskPlanningMode: String, Codable, CaseIterable, Identifiable {
    case anytime
    case exact
    case window

    var id: Self { self }
    var title: String {
        switch self {
        case .anytime: "Anytime"
        case .exact: "Exact time"
        case .window: "Flexible window"
        }
    }
}

enum SystemReviewKind: String, Codable {
    case morning
    case evening
}

struct SystemGoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var desiredOutcome: String
    var targetDate: Date?
    var isActive = true
    var createdAt = Date.now
}

struct PersonalSystem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var purpose: String
    var icon: String
    var colorName: String
    var cadence: SystemCadence
    var goalID: UUID?
    var evidenceCategory: LogCategory
    var weeklyTarget: Int
    var isActive = true
    var createdAt = Date.now
}

struct ProcessStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var order: Int
}

struct SystemProcess: Identifiable, Codable, Hashable {
    var id = UUID()
    var systemID: UUID
    var title: String
    var trigger: String
    var steps: [ProcessStep]
}

struct SystemAction: Identifiable, Codable, Hashable {
    var id = UUID()
    var systemID: UUID?
    var processID: UUID?
    var title: String
    var scheduledDate: Date
    var cadence: SystemCadence?
    var durationMinutes: Int
    var energy: ActionEnergy
    var priority: Int
    var lastCompletedAt: Date?
    var isActive = true
    var planningMode: TaskPlanningMode?
    var windowEndDate: Date?

    var effectivePlanningMode: TaskPlanningMode { planningMode ?? .exact }

    func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive else { return false }
        guard let cadence else { return calendar.isDate(scheduledDate, inSameDayAs: date) }
        switch cadence {
        case .daily:
            return date >= calendar.startOfDay(for: scheduledDate)
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return date >= calendar.startOfDay(for: scheduledDate) && (2...6).contains(weekday)
        case .weekly:
            return calendar.component(.weekday, from: scheduledDate) == calendar.component(.weekday, from: date)
        }
    }

    func isCompleted(on date: Date, calendar: Calendar = .current) -> Bool {
        lastCompletedAt.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }
}

struct SystemReview: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var kind: SystemReviewKind
    var energy: Int
    var intention: String
    var worked: String
    var friction: String
    var adjustment: String
    var completedAt = Date.now
}

enum TodayWidgetKind: String, Codable, CaseIterable, Identifiable {
    case overview
    case now
    case nextActions
    case schedule
    case review
    case progress

    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Daily overview"
        case .now: "Now"
        case .nextActions: "Next actions"
        case .schedule: "Schedule"
        case .review: "Daily review"
        case .progress: "System progress"
        }
    }
    var systemImage: String {
        switch self {
        case .overview: "circle.dotted.circle"
        case .now: "scope"
        case .nextActions: "list.bullet.rectangle"
        case .schedule: "calendar"
        case .review: "sparkles.rectangle.stack"
        case .progress: "chart.line.uptrend.xyaxis"
        }
    }
}

enum DashboardWidgetSize: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case expanded

    var id: Self { self }
    var displayName: String { rawValue.capitalized }
    var next: Self {
        switch self {
        case .compact: .standard
        case .standard: .expanded
        case .expanded: .compact
        }
    }
}

struct DashboardWidgetConfiguration: Identifiable, Codable, Hashable {
    var kind: TodayWidgetKind
    var size: DashboardWidgetSize
    var isVisible = true
    var id: TodayWidgetKind { kind }

    static let defaults: [Self] = [
        Self(kind: .overview, size: .standard),
        Self(kind: .now, size: .expanded),
        Self(kind: .nextActions, size: .standard),
        Self(kind: .schedule, size: .standard),
        Self(kind: .review, size: .compact),
        Self(kind: .progress, size: .expanded)
    ]
}

struct SavingContribution: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Double
    var date = Date.now
    var note: String = ""
}

struct SavingPlan: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var targetAmount: Double
    var targetDate: Date?
    var contributions: [SavingContribution] = []
    var createdAt = Date.now

    var savedAmount: Double { contributions.reduce(0) { $0 + $1.amount } }
    var progress: Double { targetAmount <= 0 ? 0 : min(savedAmount / targetAmount, 1) }
}

struct TripBudgetPlan: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var destination: String
    var budget: Double
    var startDate: Date
    var endDate: Date
    var expenseEntryIDs: [UUID] = []
    var createdAt = Date.now
}

enum PersonalFinanceEntryKind: String, Codable, CaseIterable, Identifiable {
    case income
    case saving
    case investment

    var id: Self { self }
    var title: String {
        switch self {
        case .income: "Income"
        case .saving: "Saving"
        case .investment: "Investment"
        }
    }
    var systemImage: String {
        switch self {
        case .income: "arrow.down.circle.fill"
        case .saving: "banknote.fill"
        case .investment: "chart.line.uptrend.xyaxis.circle.fill"
        }
    }
}

struct PersonalFinanceEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: PersonalFinanceEntryKind
    var amount: Double
    var date = Date.now
    var note: String = ""
}

enum BalanceSheetCategory: String, Codable, CaseIterable, Identifiable {
    case cash
    case investments
    case property
    case otherAsset
    case creditCard
    case loan
    case otherLiability

    var id: Self { self }
    var isAsset: Bool {
        switch self {
        case .cash, .investments, .property, .otherAsset: true
        case .creditCard, .loan, .otherLiability: false
        }
    }
    var title: String {
        switch self {
        case .cash: "Cash & bank"
        case .investments: "Investments"
        case .property: "Property & valuables"
        case .otherAsset: "Other asset"
        case .creditCard: "Credit card"
        case .loan: "Loan"
        case .otherLiability: "Other debt"
        }
    }
    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .investments: "chart.line.uptrend.xyaxis"
        case .property: "house"
        case .otherAsset: "shippingbox"
        case .creditCard: "creditcard"
        case .loan: "building.columns"
        case .otherLiability: "doc.text"
        }
    }
}

struct BalanceSheetItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var balance: Double
    var category: BalanceSheetCategory
    var updatedAt = Date.now
}

struct FinanceWorkspace: Codable, Hashable {
    var monthlyBudget: Double?
    var moneyCycleStartDay: Int
    var savingPlans: [SavingPlan]
    var trips: [TripBudgetPlan]
    var moneyEntries: [PersonalFinanceEntry]
    var balanceSheetItems: [BalanceSheetItem]

    init(
        monthlyBudget: Double?,
        moneyCycleStartDay: Int = 1,
        savingPlans: [SavingPlan],
        trips: [TripBudgetPlan],
        moneyEntries: [PersonalFinanceEntry] = [],
        balanceSheetItems: [BalanceSheetItem] = []
    ) {
        self.monthlyBudget = monthlyBudget
        self.moneyCycleStartDay = min(max(moneyCycleStartDay, 1), 31)
        self.savingPlans = savingPlans
        self.trips = trips
        self.moneyEntries = moneyEntries
        self.balanceSheetItems = balanceSheetItems
    }

    private enum CodingKeys: String, CodingKey {
        case monthlyBudget, moneyCycleStartDay, savingPlans, trips, moneyEntries, balanceSheetItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlyBudget = try container.decodeIfPresent(Double.self, forKey: .monthlyBudget)
        moneyCycleStartDay = min(max(try container.decodeIfPresent(Int.self, forKey: .moneyCycleStartDay) ?? 1, 1), 31)
        savingPlans = try container.decodeIfPresent([SavingPlan].self, forKey: .savingPlans) ?? []
        trips = try container.decodeIfPresent([TripBudgetPlan].self, forKey: .trips) ?? []
        moneyEntries = try container.decodeIfPresent([PersonalFinanceEntry].self, forKey: .moneyEntries) ?? []
        balanceSheetItems = try container.decodeIfPresent([BalanceSheetItem].self, forKey: .balanceSheetItems) ?? []
    }

    static let empty = FinanceWorkspace(monthlyBudget: nil, savingPlans: [], trips: [])
}

struct MoneyCyclePeriod {
    static func interval(
        containing reference: Date,
        startDay: Int,
        offset: Int = 0,
        calendar: Calendar = .current
    ) -> DateInterval {
        let day = min(max(startDay, 1), 31)
        let referenceMonth = calendar.dateInterval(of: .month, for: reference)?.start
            ?? calendar.startOfDay(for: reference)
        let candidate = date(inMonthOf: referenceMonth, offset: 0, day: day, calendar: calendar)
        let anchorOffset = reference < candidate ? -1 : 0
        let start = date(inMonthOf: referenceMonth, offset: anchorOffset + offset, day: day, calendar: calendar)
        let end = date(inMonthOf: referenceMonth, offset: anchorOffset + offset + 1, day: day, calendar: calendar)
        return DateInterval(start: start, end: end)
    }

    private static func date(
        inMonthOf month: Date,
        offset: Int,
        day: Int,
        calendar: Calendar
    ) -> Date {
        let targetMonth = calendar.date(byAdding: .month, value: offset, to: month) ?? month
        let lastDay = calendar.range(of: .day, in: .month, for: targetMonth)?.count ?? 28
        return calendar.date(byAdding: .day, value: min(day, lastDay) - 1, to: targetMonth) ?? targetMonth
    }
}

enum TrackerFamily: String, Codable, CaseIterable, Identifiable {
    case money = "Money"
    case booksMedia = "Books & Media"
    case habits = "Habits"
    case things = "Things"
    case health = "Health"
    case mindset = "Mindset"

    var id: Self { self }
    static let everydayCases: [Self] = [.health, .habits, .booksMedia, .mindset]

    var subtitle: String {
        switch self {
        case .money: "Spending, saving and trips"
        case .booksMedia: "Books, novels and things to watch"
        case .habits: "Small actions you want to repeat"
        case .things: "Wish lists, checklists and reminders"
        case .health: "Movement, sleep, food and energy"
        case .mindset: "Mood, reflection and mental wellbeing"
        }
    }

    var systemImage: String {
        switch self {
        case .money: "wallet.bifold"
        case .booksMedia: "books.vertical"
        case .habits: "repeat.circle"
        case .things: "checklist"
        case .health: "heart.text.square"
        case .mindset: "brain.head.profile"
        }
    }
}

enum TrackerTemplate: String, Codable, CaseIterable, Identifiable {
    case spending = "Spending"
    case saving = "Saving goal"
    case trip = "Trip spending"
    case books = "Books"
    case novels = "Novels"
    case documentaries = "Documentaries"
    case movies = "Movies & series"
    case dailyHabit = "Daily habit"
    case weeklyHabit = "Weekly habit"
    case wishlist = "Wish list"
    case checklist = "Checklist"
    case reminders = "Reminders"
    case movement = "Movement"
    case sleep = "Sleep"
    case meals = "Food & meals"
    case energy = "Energy"
    case mood = "Mood"
    case journal = "Journal"
    case meditation = "Mindful minutes"

    var id: Self { self }

    var family: TrackerFamily {
        switch self {
        case .spending, .saving, .trip: .money
        case .books, .novels, .documentaries, .movies: .booksMedia
        case .dailyHabit, .weeklyHabit: .habits
        case .wishlist, .checklist, .reminders: .things
        case .movement, .sleep, .meals, .energy: .health
        case .mood, .journal, .meditation: .mindset
        }
    }

    var category: LogCategory {
        switch self {
        case .spending, .trip: .expense
        case .saving: .note
        case .books, .novels: .book
        case .documentaries, .movies: .movie
        case .dailyHabit, .weeklyHabit: .routine
        case .wishlist, .checklist, .reminders: .list
        case .movement: .fitness
        case .sleep: .sleep
        case .meals: .food
        case .energy, .mood: .mood
        case .journal: .journal
        case .meditation: .routine
        }
    }

    var systemImage: String {
        switch self {
        case .spending: "creditcard"
        case .saving: "banknote"
        case .trip: "airplane"
        case .books: "book.closed"
        case .novels: "text.book.closed"
        case .documentaries: "play.rectangle"
        case .movies: "film"
        case .dailyHabit: "sun.max"
        case .weeklyHabit: "calendar.badge.checkmark"
        case .wishlist: "heart"
        case .checklist: "checklist"
        case .reminders: "bell"
        case .movement: "figure.walk"
        case .sleep: "bed.double"
        case .meals: "fork.knife"
        case .energy: "bolt.heart"
        case .mood: "face.smiling"
        case .journal: "book.pages"
        case .meditation: "figure.mind.and.body"
        }
    }

    var prompt: String {
        switch self {
        case .spending: "Record an expense and amount"
        case .saving: "Add money without counting it as spending"
        case .trip: "Keep travel costs together"
        case .books: "Build a reading list and update progress"
        case .novels: "Keep novels separate from other books"
        case .documentaries: "Plan and record documentaries"
        case .movies: "Keep a watch list"
        case .dailyHabit: "Tick off one action each day"
        case .weeklyHabit: "Build consistency across the week"
        case .wishlist: "Save things you may want to buy"
        case .checklist: "Keep a simple list of things to do"
        case .reminders: "Add something with a due date"
        case .movement: "Record walks, workouts and active time"
        case .sleep: "See your sleep pattern over time"
        case .meals: "Remember meals and how they felt"
        case .energy: "Notice when your energy rises and falls"
        case .mood: "Check in with how you feel"
        case .journal: "Keep reflections linked to your timeline"
        case .meditation: "Record time spent slowing down"
        }
    }

    var usesAmount: Bool {
        self == .spending || self == .saving || self == .trip
    }

    var usesStatus: Bool {
        family == .booksMedia
    }

    var usesDuration: Bool {
        family == .habits || self == .movement || self == .sleep || self == .meditation
    }

    var usesDueDate: Bool {
        family == .things
    }
}

struct TrackerDefinition: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var template: TrackerTemplate
    var isStarter = false
    var createdAt = Date.now

    var family: TrackerFamily { template.family }
}

struct SystemWorkspace: Codable {
    var goals: [SystemGoal]
    var systems: [PersonalSystem]
    var processes: [SystemProcess]
    var actions: [SystemAction]
    var reviews: [SystemReview]
    var dashboardLayout: [DashboardWidgetConfiguration]?
    var financeWorkspace: FinanceWorkspace?
    var trackers: [TrackerDefinition]?

    static let empty = SystemWorkspace(goals: [], systems: [], processes: [], actions: [], reviews: [], dashboardLayout: nil, financeWorkspace: nil, trackers: nil)
}

@Model
final class SystemWorkspaceRecord {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date
    var revision: Int
    var modifiedByDevice: String

    init(key: String = "primary", payload: Data) {
        self.key = key
        self.payload = payload
        updatedAt = .now
        revision = 1
        modifiedByDevice = DeviceIdentity.current
    }
}

@MainActor
protocol SystemRepository {
    func load() throws -> SystemWorkspace
    func save(_ workspace: SystemWorkspace) throws
}

@MainActor
final class SwiftDataSystemRepository: SystemRepository {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        context = container.mainContext
        context.autosaveEnabled = false
    }

    func load() throws -> SystemWorkspace {
        let descriptor = FetchDescriptor<SystemWorkspaceRecord>()
        guard let record = try context.fetch(descriptor).first else { return .empty }
        return try decoder.decode(SystemWorkspace.self, from: record.payload)
    }

    func save(_ workspace: SystemWorkspace) throws {
        let data = try encoder.encode(workspace)
        let descriptor = FetchDescriptor<SystemWorkspaceRecord>()
        if let record = try context.fetch(descriptor).first {
            record.payload = data
            record.updatedAt = .now
            record.revision += 1
            record.modifiedByDevice = DeviceIdentity.current
        } else {
            context.insert(SystemWorkspaceRecord(payload: data))
        }
        try context.save()
    }
}

struct TodaySystemSnapshot {
    var date: Date
    var actions: [SystemAction]
    var completedCount: Int
    var systemProgress: [SystemProgress]
    var morningReview: SystemReview?
    var eveningReview: SystemReview?

    var currentAction: SystemAction? { actions.first { !$0.isCompleted(on: date) } }
    var nextActions: [SystemAction] { actions.filter { !$0.isCompleted(on: date) }.dropFirst().prefix(3).map { $0 } }
}

struct SystemProgress: Identifiable {
    var id: UUID { system.id }
    var system: PersonalSystem
    var evidenceCount: Int
    var target: Int

    var fraction: Double { target == 0 ? 0 : min(Double(evidenceCount) / Double(target), 1) }
}

struct TodaySystemEngine {
    func snapshot(
        on date: Date,
        workspace: SystemWorkspace,
        timeline: [LogEntry],
        calendar: Calendar = .current
    ) -> TodaySystemSnapshot {
        let actions = workspace.actions
            .filter { $0.occurs(on: date, calendar: calendar) }
            .sorted {
                if $0.isCompleted(on: date, calendar: calendar) != $1.isCompleted(on: date, calendar: calendar) {
                    return !$0.isCompleted(on: date, calendar: calendar)
                }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.scheduledDate < $1.scheduledDate
            }
        let week = calendar.dateInterval(of: .weekOfYear, for: date)
        let progress = workspace.systems.filter(\.isActive).map { system in
            let count = timeline.filter { entry in
                entry.category == system.evidenceCategory && (week?.contains(entry.timestamp) ?? false)
            }.count
            return SystemProgress(system: system, evidenceCount: count, target: system.weeklyTarget)
        }
        let reviews = workspace.reviews.filter { calendar.isDate($0.date, inSameDayAs: date) }
        return TodaySystemSnapshot(
            date: date,
            actions: actions,
            completedCount: actions.filter { $0.isCompleted(on: date, calendar: calendar) }.count,
            systemProgress: progress,
            morningReview: reviews.first { $0.kind == .morning },
            eveningReview: reviews.first { $0.kind == .evening }
        )
    }
}

@MainActor
@Observable
final class SystemFeatureModel {
    private(set) var workspace: SystemWorkspace
    private let repository: SystemRepository
    private let engine: TodaySystemEngine

    init(repository: SystemRepository, engine: TodaySystemEngine) {
        self.repository = repository
        self.engine = engine
        workspace = (try? repository.load()) ?? .empty
        if workspace.systems.isEmpty {
            workspace = Self.starterWorkspace()
            try? repository.save(workspace)
        }
        if workspace.trackers == nil {
            workspace.trackers = Self.starterTrackers()
            try? repository.save(workspace)
        } else {
            var current = workspace.trackers ?? []
            var addedEverydayStarter = false
            if !current.contains(where: { $0.family == .health }) {
                current.append(TrackerDefinition(name: "Movement", template: .movement, isStarter: true))
                addedEverydayStarter = true
            }
            if !current.contains(where: { $0.family == .mindset }) {
                current.append(TrackerDefinition(name: "Mood", template: .mood, isStarter: true))
                addedEverydayStarter = true
            }
            if addedEverydayStarter {
                workspace.trackers = current
                try? repository.save(workspace)
            }
        }
    }

    func snapshot(on date: Date, timeline: [LogEntry]) -> TodaySystemSnapshot {
        engine.snapshot(on: date, workspace: workspace, timeline: timeline)
    }

    var dashboardLayout: [DashboardWidgetConfiguration] {
        workspace.dashboardLayout ?? DashboardWidgetConfiguration.defaults
    }

    var hiddenDashboardWidgets: [DashboardWidgetConfiguration] {
        dashboardLayout.filter { !$0.isVisible }
    }

    var financeWorkspace: FinanceWorkspace {
        workspace.financeWorkspace ?? .empty
    }

    var trackers: [TrackerDefinition] {
        workspace.trackers ?? []
    }

    func addTracker(name: String, template: TrackerTemplate) -> TrackerDefinition {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tracker = TrackerDefinition(name: trimmedName.isEmpty ? template.rawValue : trimmedName, template: template)
        var current = trackers
        current.append(tracker)
        workspace.trackers = current
        persist()
        return tracker
    }

    func setMonthlyBudget(_ amount: Double?) {
        updateFinance { $0.monthlyBudget = amount }
    }

    func setMoneyCycleStartDay(_ day: Int) {
        updateFinance { $0.moneyCycleStartDay = min(max(day, 1), 31) }
    }

    func addSavingPlan(name: String, targetAmount: Double, targetDate: Date?) {
        updateFinance {
            $0.savingPlans.append(SavingPlan(name: name, targetAmount: targetAmount, targetDate: targetDate))
        }
    }

    func addSavingContribution(planID: UUID, amount: Double, note: String) {
        updateFinance { finance in
            guard let index = finance.savingPlans.firstIndex(where: { $0.id == planID }) else { return }
            finance.savingPlans[index].contributions.append(
                SavingContribution(amount: amount, note: note)
            )
        }
    }

    func upsertTrip(_ trip: TripBudgetPlan) {
        updateFinance { finance in
            if let index = finance.trips.firstIndex(where: { $0.id == trip.id }) {
                finance.trips[index] = trip
            } else {
                finance.trips.append(trip)
            }
        }
    }

    func deleteTrip(_ id: UUID) {
        updateFinance { $0.trips.removeAll { $0.id == id } }
    }

    func addMoneyEntry(kind: PersonalFinanceEntryKind, amount: Double, date: Date, note: String) {
        updateFinance {
            $0.moneyEntries.append(PersonalFinanceEntry(kind: kind, amount: amount, date: date, note: note))
        }
    }

    func upsertMoneyEntry(_ entry: PersonalFinanceEntry) {
        updateFinance { finance in
            if let index = finance.moneyEntries.firstIndex(where: { $0.id == entry.id }) {
                finance.moneyEntries[index] = entry
            } else {
                finance.moneyEntries.append(entry)
            }
        }
    }

    func deleteMoneyEntry(_ id: UUID) {
        updateFinance { $0.moneyEntries.removeAll { $0.id == id } }
    }

    func upsertBalanceSheetItem(_ item: BalanceSheetItem) {
        updateFinance { finance in
            var updated = item
            updated.updatedAt = .now
            if let index = finance.balanceSheetItems.firstIndex(where: { $0.id == item.id }) {
                finance.balanceSheetItems[index] = updated
            } else {
                finance.balanceSheetItems.append(updated)
            }
        }
    }

    func deleteBalanceSheetItem(_ id: UUID) {
        updateFinance { $0.balanceSheetItems.removeAll { $0.id == id } }
    }

    func linkExpense(_ entryID: UUID, toTrip tripID: UUID) {
        updateFinance { finance in
            guard let index = finance.trips.firstIndex(where: { $0.id == tripID }) else { return }
            if !finance.trips[index].expenseEntryIDs.contains(entryID) {
                finance.trips[index].expenseEntryIDs.append(entryID)
            }
        }
    }

    func moveDashboardWidget(_ source: TodayWidgetKind, before destination: TodayWidgetKind) {
        var layout = dashboardLayout
        guard source != destination,
              let sourceIndex = layout.firstIndex(where: { $0.kind == source }),
              let destinationIndex = layout.firstIndex(where: { $0.kind == destination }) else { return }
        let item = layout.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        layout.insert(item, at: adjustedDestination)
        workspace.dashboardLayout = layout
        persist()
    }

    func cycleDashboardWidgetSize(_ kind: TodayWidgetKind) {
        updateDashboardWidget(kind) { $0.size = $0.size.next }
    }

    func setDashboardWidgetSize(_ kind: TodayWidgetKind, size: DashboardWidgetSize) {
        updateDashboardWidget(kind) { $0.size = size }
    }

    func setDashboardWidget(_ kind: TodayWidgetKind, visible: Bool) {
        updateDashboardWidget(kind) { $0.isVisible = visible }
    }

    func resetDashboardLayout() {
        workspace.dashboardLayout = DashboardWidgetConfiguration.defaults
        persist()
    }

    func toggle(_ action: SystemAction, on date: Date) {
        guard let index = workspace.actions.firstIndex(where: { $0.id == action.id }) else { return }
        workspace.actions[index].lastCompletedAt = action.isCompleted(on: date) ? nil : date
        persist()
    }

    func updateAction(_ action: SystemAction) {
        guard let index = workspace.actions.firstIndex(where: { $0.id == action.id }) else { return }
        workspace.actions[index] = action
        persist()
    }

    func upsertAction(_ action: SystemAction) {
        if let index = workspace.actions.firstIndex(where: { $0.id == action.id }) {
            workspace.actions[index] = action
        } else {
            workspace.actions.append(action)
        }
        persist()
    }

    func deleteAction(_ actionID: UUID) {
        workspace.actions.removeAll { $0.id == actionID }
        persist()
    }

    func postponeAction(_ actionID: UUID, to date: Date) {
        guard let index = workspace.actions.firstIndex(where: { $0.id == actionID }) else { return }
        let duration = workspace.actions[index].windowEndDate.map {
            $0.timeIntervalSince(workspace.actions[index].scheduledDate)
        }
        workspace.actions[index].scheduledDate = date
        if let duration { workspace.actions[index].windowEndDate = date.addingTimeInterval(duration) }
        workspace.actions[index].cadence = nil
        workspace.actions[index].lastCompletedAt = nil
        persist()
    }

    func saveReview(_ review: SystemReview) {
        let calendar = Calendar.current
        workspace.reviews.removeAll { $0.kind == review.kind && calendar.isDate($0.date, inSameDayAs: review.date) }
        workspace.reviews.append(review)
        persist()
    }

    private func persist() {
        try? repository.save(workspace)
    }

    private func updateDashboardWidget(
        _ kind: TodayWidgetKind,
        change: (inout DashboardWidgetConfiguration) -> Void
    ) {
        var layout = dashboardLayout
        guard let index = layout.firstIndex(where: { $0.kind == kind }) else { return }
        change(&layout[index])
        workspace.dashboardLayout = layout
        persist()
    }

    private func updateFinance(change: (inout FinanceWorkspace) -> Void) {
        var finance = financeWorkspace
        change(&finance)
        workspace.financeWorkspace = finance
        persist()
    }

    private static func starterWorkspace() -> SystemWorkspace {
        let goal = SystemGoal(
            title: "Build a balanced, intentional life",
            desiredOutcome: "Make steady progress without sacrificing health or recovery."
        )
        let focus = PersonalSystem(
            title: "Focused work",
            purpose: "Protect attention for meaningful work.",
            icon: "brain.head.profile",
            colorName: "blue",
            cadence: .weekdays,
            goalID: goal.id,
            evidenceCategory: .work,
            weeklyTarget: 5
        )
        let movement = PersonalSystem(
            title: "Daily movement",
            purpose: "Create energy through consistent movement.",
            icon: "figure.walk",
            colorName: "green",
            cadence: .daily,
            goalID: goal.id,
            evidenceCategory: .fitness,
            weeklyTarget: 5
        )
        let reset = PersonalSystem(
            title: "Evening reset",
            purpose: "Close today and make tomorrow easier.",
            icon: "moon.stars.fill",
            colorName: "purple",
            cadence: .daily,
            goalID: goal.id,
            evidenceCategory: .routine,
            weeklyTarget: 7
        )

        let focusProcess = SystemProcess(
            systemID: focus.id,
            title: "Start a focus block",
            trigger: "First protected opening in the workday",
            steps: [
                ProcessStep(title: "Choose one outcome", order: 0),
                ProcessStep(title: "Remove distractions", order: 1),
                ProcessStep(title: "Work for one protected block", order: 2),
                ProcessStep(title: "Record the result", order: 3)
            ]
        )
        let movementProcess = SystemProcess(
            systemID: movement.id,
            title: "Move after lunch",
            trigger: "After lunch",
            steps: [
                ProcessStep(title: "Put on walking shoes", order: 0),
                ProcessStep(title: "Walk for at least 20 minutes", order: 1),
                ProcessStep(title: "Let Health record the evidence", order: 2)
            ]
        )
        let resetProcess = SystemProcess(
            systemID: reset.id,
            title: "Close the day",
            trigger: "At 20:30",
            steps: [
                ProcessStep(title: "Review what happened", order: 0),
                ProcessStep(title: "Name the main friction", order: 1),
                ProcessStep(title: "Choose tomorrow’s first action", order: 2)
            ]
        )

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let focusTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today
        let movementTime = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: today) ?? today
        let resetTime = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: today) ?? today
        return SystemWorkspace(
            goals: [goal],
            systems: [focus, movement, reset],
            processes: [focusProcess, movementProcess, resetProcess],
            actions: [
                SystemAction(systemID: focus.id, processID: focusProcess.id, title: "Protect one focus block", scheduledDate: focusTime, cadence: .weekdays, durationMinutes: 60, energy: .high, priority: 3),
                SystemAction(systemID: movement.id, processID: movementProcess.id, title: "Move for 30 minutes", scheduledDate: movementTime, cadence: .daily, durationMinutes: 30, energy: .medium, priority: 2),
                SystemAction(systemID: reset.id, processID: resetProcess.id, title: "Reflect and prepare tomorrow", scheduledDate: resetTime, cadence: .daily, durationMinutes: 10, energy: .low, priority: 1)
            ],
            reviews: [],
            dashboardLayout: DashboardWidgetConfiguration.defaults,
            financeWorkspace: .empty,
            trackers: starterTrackers()
        )
    }

    private static func starterTrackers() -> [TrackerDefinition] {
        [
            TrackerDefinition(name: "Movement", template: .movement, isStarter: true),
            TrackerDefinition(name: "Books", template: .books, isStarter: true),
            TrackerDefinition(name: "Daily habits", template: .dailyHabit, isStarter: true),
            TrackerDefinition(name: "Mood", template: .mood, isStarter: true)
        ]
    }
}
