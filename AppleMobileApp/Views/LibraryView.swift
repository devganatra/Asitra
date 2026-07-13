import Charts
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var collection: CollectionKind = .books
    @State private var statusFilter: EntryStatus?

    private var entries: [LogEntry] {
        model.entries.filter { entry in
            let matchesCollection = entry.category == collection.category
            let matchesStatus = statusFilter == nil || entry.status == statusFilter
            return matchesCollection && matchesStatus
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Collection", selection: $collection) {
                ForEach(CollectionKind.allCases) { collection in
                    Label(collection.rawValue, systemImage: collection.systemImage)
                        .tag(collection)
                }
            }
            .pickerStyle(.segmented)
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

            if entries.isEmpty {
                ContentUnavailableView(
                    "No \(collection.rawValue.lowercased()) yet",
                    systemImage: collection.systemImage,
                    description: Text(collection.emptyMessage)
                )
                .frame(maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    HStack(spacing: 14) {
                        Image(systemName: entry.category.systemImage)
                            .font(.title2)
                            .foregroundStyle(collection.color)
                            .frame(width: 38, height: 38)
                            .background(collection.color.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.headline)
                            HStack {
                                if let status = entry.status {
                                    Text(status.rawValue)
                                }
                                Text(entry.timestamp, format: .dateTime.day().month(.abbreviated).year())
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("Collections")
        .onChange(of: collection) { _, newValue in
            if !newValue.supportsStatus { statusFilter = nil }
        }
    }
}

private enum CollectionKind: String, CaseIterable, Identifiable {
    case books = "Books"
    case movies = "Movies"
    case ideas = "Ideas"

    var id: Self { self }
    var category: LogCategory {
        switch self {
        case .books: .book
        case .movies: .movie
        case .ideas: .idea
        }
    }
    var systemImage: String { category.systemImage }
    var supportsStatus: Bool { self != .ideas }
    var color: Color {
        switch self {
        case .books: .indigo
        case .movies: .red
        case .ideas: .yellow
        }
    }
    var emptyMessage: String {
        switch self {
        case .books: "Log “want to read…” or “finished…” to build your reading list."
        case .movies: "Log “want to watch…” or “watched…” to build your watchlist."
        case .ideas: "Start an entry with “idea” and Dayline will collect it here."
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
