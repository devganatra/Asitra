import Charts
import SwiftUI

struct ListsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedKind: ListKind?

    private var listEntries: [LogEntry] {
        model.entries.filter {
            $0.category == .list && (selectedKind == nil || $0.listKind == selectedKind)
        }
    }

    private var pending: [LogEntry] { listEntries.filter { !$0.isCompleted } }
    private var completed: [LogEntry] { listEntries.filter { $0.isCompleted } }

    var body: some View {
        VStack(spacing: 0) {
            Picker("List", selection: $selectedKind) {
                Text("All").tag(ListKind?.none)
                ForEach(ListKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.systemImage)
                        .tag(ListKind?.some(kind))
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if listEntries.isEmpty {
                ContentUnavailableView {
                    Label("Your lists are empty", systemImage: "checklist")
                } description: {
                    Text("From Today, log “buy milk” or “remind me to call tomorrow at 6pm.”")
                } actions: {
                    Button("Go to Today") { model.selectedSection = .today }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    if !pending.isEmpty {
                        Section("Open") {
                            ForEach(pending) { entry in
                                ListEntryRow(entry: entry)
                            }
                        }
                    }

                    if !completed.isEmpty {
                        Section("Completed") {
                            ForEach(completed) { entry in
                                ListEntryRow(entry: entry)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Lists")
    }

    @ViewBuilder
    private func ListEntryRow(entry: LogEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                model.toggleCompleted(entry)
            } label: {
                Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .strikethrough(entry.isCompleted)
                    .foregroundStyle(entry.isCompleted ? .secondary : .primary)

                HStack(spacing: 10) {
                    if let kind = entry.listKind {
                        Label(kind.displayName, systemImage: kind.systemImage)
                    }
                    if let dueDate = entry.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                            .foregroundStyle(!entry.isCompleted && dueDate < .now ? .red : .secondary)
                    }
                    if entry.appleReminderIdentifier != nil {
                        Label("Apple Reminders", systemImage: "checkmark.icloud")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete", role: .destructive) { model.delete(entry) }
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var collection: CollectionKind = .books
    @State private var statusFilter: EntryStatus?

    private var items: [TrackedCollectionItem] {
        let matchingEntries = model.entries.filter { $0.category == collection.category }
        let grouped = Dictionary(grouping: matchingEntries, by: { $0.collectionKey })
        return grouped.compactMap { key, events in
            guard let latest = events.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return TrackedCollectionItem(
                id: key,
                title: latest.collectionDisplayTitle,
                latest: latest,
                eventCount: events.count
            )
        }
        .filter { statusFilter == nil || $0.latest.status == statusFilter }
        .sorted { $0.latest.timestamp > $1.latest.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Collection", selection: $collection) {
                ForEach(CollectionKind.allCases) { collection in
                    Label(collection.rawValue, systemImage: collection.systemImage)
                        .tag(collection)
                }
            }
            .pickerStyle(.menu)
            .padding()

            if collection.supportsStatus {
                Picker("Status", selection: $statusFilter) {
                    Text("All").tag(EntryStatus?.none)
                    ForEach(EntryStatus.allCases) { status in
                        Text(status.rawValue).tag(EntryStatus?.some(status))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom)
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No \(collection.rawValue.lowercased()) yet",
                    systemImage: collection.systemImage,
                    description: Text(collection.emptyMessage)
                )
                .frame(maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.latest.category.systemImage)
                            .font(.title2)
                            .foregroundStyle(collection.color)
                            .frame(width: 38, height: 38)
                            .background(collection.color.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            HStack {
                                if let status = item.latest.status {
                                    Menu {
                                        ForEach(EntryStatus.allCases) { newStatus in
                                            Button(newStatus.rawValue) {
                                                model.recordCollectionStatus(
                                                    for: item.latest,
                                                    title: item.title,
                                                    status: newStatus
                                                )
                                            }
                                        }
                                    } label: {
                                        Label(status.rawValue, systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                                Text(item.latest.timestamp, format: .dateTime.day().month(.abbreviated).year())
                                if item.eventCount > 1 {
                                    Text("\(item.eventCount) timeline events")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if !item.latest.note.isEmpty {
                                Text(item.latest.note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 12) {
                                if let amount = item.latest.amount {
                                    Label(
                                        amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR")),
                                        systemImage: "creditcard"
                                    )
                                }
                                if let minutes = item.latest.durationMinutes {
                                    Label("\(minutes) min", systemImage: "clock")
                                }
                                if let source = item.latest.fitnessSource {
                                    Label(source, systemImage: "sensor")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("Trackers")
        .onChange(of: collection) { _, newValue in
            if !newValue.supportsStatus { statusFilter = nil }
        }
    }
}

private struct TrackedCollectionItem: Identifiable {
    let id: String
    let title: String
    let latest: LogEntry
    let eventCount: Int
}

private enum CollectionKind: String, CaseIterable, Identifiable {
    case books = "Books"
    case movies = "Movies"
    case habits = "Habits"
    case meals = "Food"
    case fitness = "Fitness"
    case sleep = "Sleep"
    case mindset = "Mindset"
    case journal = "Journal"
    case ideas = "Ideas"
    case expenses = "Expenses"
    case work = "Work"
    case screenTime = "Screen Time"

    var id: Self { self }
    var category: LogCategory {
        switch self {
        case .books: .book
        case .movies: .movie
        case .habits: .routine
        case .meals: .food
        case .fitness: .fitness
        case .sleep: .sleep
        case .mindset: .mood
        case .journal: .journal
        case .ideas: .idea
        case .expenses: .expense
        case .work: .work
        case .screenTime: .screenTime
        }
    }
    var systemImage: String { category.systemImage }
    var supportsStatus: Bool { self == .books || self == .movies }
    var color: Color {
        switch self {
        case .books: .indigo
        case .movies: .red
        case .habits: .blue
        case .meals: .pink
        case .fitness: .green
        case .sleep: .indigo
        case .mindset: .purple
        case .journal: .teal
        case .ideas: .yellow
        case .expenses: .orange
        case .work: .blue
        case .screenTime: .cyan
        }
    }
    var emptyMessage: String {
        switch self {
        case .books: "Log “want to read…” or “finished…” to build your reading list."
        case .movies: "Log “want to watch…” or “watched…” to build your watchlist."
        case .habits: "Routine entries from the timeline appear here automatically."
        case .meals: "Meals and food entries from the timeline appear here automatically."
        case .fitness: "Manual workouts and connected fitness sources appear here."
        case .sleep: "Sleep imported from wearables or entered manually appears here."
        case .mindset: "Mood and mindset entries from the timeline appear here."
        case .journal: "Your journal entries remain organized here."
        case .ideas: "Start an entry with “idea” and Sakhya will collect it here."
        case .expenses: "Purchases and spending entries from the timeline appear here."
        case .work: "Work sessions and events from the timeline appear here."
        case .screenTime: "Phone and computer usage entries appear here."
        }
    }
}

struct BalanceView: View {
    @Environment(AppModel.self) private var model

    private var days: [Date] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now))
        }
    }

    private var workMinutes: Int { total(.work) }
    private var personalMinutes: Int { total(.personal) }
    private var restMinutes: Int { total(.rest) }
    private var screenMinutes: Int { days.map(model.screenMinutes(on:)).reduce(0, +) }
    private var score: Int { model.balanceScore(for: days) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 24) {
                    Gauge(value: Double(score), in: 0...100) {
                        Text("Balance")
                    } currentValueLabel: {
                        Text("\(score)")
                            .font(.title.bold())
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.teal)
                    .scaleEffect(1.35)
                    .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your 7-day balance")
                            .font(.title2.bold())
                        Text(balanceMessage)
                            .foregroundStyle(.secondary)
                        Text("Based only on time you have logged so far.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    InsightCard(title: "Work", value: format(workMinutes), icon: "briefcase", color: .blue)
                    InsightCard(title: "Personal", value: format(personalMinutes), icon: "house", color: .green)
                    InsightCard(title: "Rest", value: format(restMinutes), icon: "moon.zzz", color: .indigo)
                    InsightCard(title: "Screen time", value: format(screenMinutes), icon: "hourglass", color: .cyan)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Work and personal time")
                        .font(.title2.bold())
                    Chart(days, id: \.self) { day in
                        BarMark(
                            x: .value("Day", day, unit: .day),
                            y: .value("Minutes", model.trackedMinutes(.work, on: day))
                        )
                        .foregroundStyle(by: .value("Area", "Work"))

                        BarMark(
                            x: .value("Day", day, unit: .day),
                            y: .value("Minutes", model.trackedMinutes(.personal, on: day))
                        )
                        .foregroundStyle(by: .value("Area", "Personal"))
                    }
                    .chartForegroundStyleScale(["Work": Color.blue, "Personal": Color.green])
                    .frame(height: 240)
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Label("Automatic Screen Time connection", systemImage: "lock.shield")
                        .font(.headline)
                    Text("The balance dashboard already accepts phone, tablet, Mac, web, and offline time from smart capture. Automatic per-app usage requires Apple’s Family Controls entitlement and a privacy-preserving Device Activity report extension.")
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Work-Life Balance")
    }

    private func total(_ area: LifeArea) -> Int {
        days.map { model.trackedMinutes(area, on: $0) }.reduce(0, +)
    }

    private func format(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private var balanceMessage: String {
        guard workMinutes + personalMinutes > 0 else {
            return "Log work and personal activities with a duration to establish your baseline."
        }
        if workMinutes > personalMinutes * 2 {
            return "Work is taking most of your tracked time. Consider protecting a personal block tomorrow."
        }
        if screenMinutes > personalMinutes && screenMinutes > 180 {
            return "A large share of personal time is screen-based. A screen-free activity may help you reset."
        }
        return "Your tracked work and personal time are reasonably balanced. Keep protecting both."
    }
}

struct InsightsView: View {
    @Environment(AppModel.self) private var model

    private var days: [Date] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now))
        }
    }

    private var recentEntries: [LogEntry] {
        let start = days.first ?? .now
        return model.entries.filter { $0.timestamp >= start }
    }

    private var weekExpense: Double { days.map(model.expense(on:)).reduce(0, +) }
    private var weekActiveMinutes: Int { days.map(model.activeMinutes(on:)).reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    InsightCard(title: "Spending", value: weekExpense.formatted(.currency(code: currencyCode)), icon: "creditcard", color: .orange)
                    InsightCard(title: "Activity", value: "\(weekActiveMinutes) min", icon: "figure.walk", color: .green)
                    InsightCard(title: "Sleep", value: formatSleep(), icon: "bed.double", color: .indigo)
                    InsightCard(title: "Meals", value: "\(count(.food))", icon: "fork.knife", color: .pink)
                    InsightCard(title: "Habits", value: "\(count(.routine))", icon: "checkmark.circle", color: .blue)
                    InsightCard(title: "Mindset", value: "\(count(.mood))", icon: "brain.head.profile", color: .purple)
                    InsightCard(title: "Journal", value: "\(count(.journal))", icon: "book.pages", color: .teal)
                }

                chartSection(title: "Spending") {
                    Chart(days, id: \.self) { day in
                        BarMark(x: .value("Day", day, unit: .day), y: .value("Spent", model.expense(on: day)))
                            .foregroundStyle(.orange.gradient)
                    }
                }

                chartSection(title: "Active minutes") {
                    Chart(days, id: \.self) { day in
                        BarMark(x: .value("Day", day, unit: .day), y: .value("Minutes", model.activeMinutes(on: day)))
                            .foregroundStyle(.green.gradient)
                    }
                }

                chartSection(title: "What you logged") {
                    Chart(LogCategory.allCases, id: \.self) { category in
                        BarMark(
                            x: .value("Entries", count(category)),
                            y: .value("Category", category.displayName)
                        )
                        .foregroundStyle(by: .value("Category", category.displayName))
                    }
                    .chartLegend(.hidden)
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("7-Day Insights")
    }

    private func count(_ category: LogCategory) -> Int {
        recentEntries.filter { $0.category == category }.count
    }

    private func formatSleep() -> String {
        let minutes = days.map(model.sleepMinutes(on:)).reduce(0, +)
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private func chartSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            content().frame(height: 220)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }
}

private struct InsightCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(value).font(.title2.bold())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
