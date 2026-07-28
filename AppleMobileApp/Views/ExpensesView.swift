import Charts
import SwiftUI

struct ExpensesView: View {
    @Environment(AppModel.self) private var model
    @Environment(SystemFeatureModel.self) private var systemFeature
    @State private var section: MoneySection = .month
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var showingBudget = false
    @State private var showingExpense = false
    @State private var expenseTripID: UUID?
    @State private var showingSavingPlan = false
    @State private var contributionPlan: SavingPlan?
    @State private var showingTrip = false

    private var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }
    private var finance: FinanceWorkspace { systemFeature.financeWorkspace }
    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: selectedMonth)
            ?? DateInterval(start: selectedMonth, duration: 2_592_000)
    }
    private var monthlyExpenses: [LogEntry] {
        model.entries.filter { $0.category == .expense && monthInterval.contains($0.timestamp) }
    }
    private var monthlySpent: Double { monthlyExpenses.compactMap(\.amount).reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            moneyHeader
            Picker("Money area", selection: $section) {
                ForEach(MoneySection.allCases) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 12)

            ScrollView {
                Group {
                    switch section {
                    case .month: monthlyView
                    case .savings: savingsView
                    case .trips: tripsView
                    }
                }
                .padding()
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Money")
        .sheet(isPresented: $showingBudget) {
            MonthlyBudgetSheet(current: finance.monthlyBudget) { systemFeature.setMonthlyBudget($0) }
        }
        .sheet(isPresented: $showingExpense, onDismiss: { expenseTripID = nil }) {
            AddExpenseSheet(trip: finance.trips.first { $0.id == expenseTripID }) { title, amount, date in
                let entry = LogEntry(
                    timestamp: date,
                    category: .expense,
                    title: title,
                    note: expenseTripID.flatMap { id in finance.trips.first { $0.id == id }?.name }.map { "Trip: \($0)" } ?? "",
                    amount: amount,
                    lifeArea: .personal,
                    deviceSource: currentDeviceSource
                )
                model.add(entry, syncToCalendar: false)
                if let tripID = expenseTripID { systemFeature.linkExpense(entry.id, toTrip: tripID) }
            }
        }
        .sheet(isPresented: $showingSavingPlan) {
            NewSavingPlanSheet { name, amount, date in
                systemFeature.addSavingPlan(name: name, targetAmount: amount, targetDate: date)
            }
        }
        .sheet(item: $contributionPlan) { plan in
            SavingContributionSheet(plan: plan) { amount, note in
                systemFeature.addSavingContribution(planID: plan.id, amount: amount, note: note)
            }
        }
        .sheet(isPresented: $showingTrip) {
            NewTripSheet { systemFeature.addTrip($0) }
        }
    }

    private var moneyHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your money")
                    .font(.largeTitle.bold())
                Text("See what you spent, save for something important, and plan trips without finance jargon.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                expenseTripID = nil
                showingExpense = true
            } label: {
                Label("Add expense", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var monthlyView: some View {
        VStack(alignment: .leading, spacing: 18) {
            monthSelector
            budgetHero
            if !monthlyExpenses.isEmpty {
                categoryBreakdown
                recentExpenses
            } else {
                ContentUnavailableView {
                    Label("No spending recorded", systemImage: "wallet.bifold")
                } description: {
                    Text("Add an expense here or write “spent €12 on lunch” in Today’s System.")
                } actions: {
                    Button("Add first expense") { showingExpense = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
    }

    private var monthSelector: some View {
        HStack {
            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title2.bold())
            Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month))
            Spacer()
            Text("\(monthlyExpenses.count) \(monthlyExpenses.count == 1 ? "expense" : "expenses")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var budgetHero: some View {
        let budget = finance.monthlyBudget
        let left = (budget ?? 0) - monthlySpent
        let progress = budget.map { $0 <= 0 ? 0 : monthlySpent / $0 } ?? 0
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SPENT THIS MONTH")
                        .font(.caption.bold())
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text(monthlySpent.formatted(.currency(code: currencyCode)))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    if budget != nil {
                        Text(left >= 0
                            ? "\(left.formatted(.currency(code: currencyCode))) left in your plan"
                            : "\((-left).formatted(.currency(code: currencyCode))) over your plan")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(left >= 0 ? .green : .red)
                    } else {
                        Text("Set a monthly plan to see how much is left.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(budget == nil ? "Set a plan" : "Change plan") { showingBudget = true }
                    .buttonStyle(.bordered)
            }
            if let budget {
                ProgressView(value: min(progress, 1))
                    .tint(progress > 1 ? .red : progress > 0.8 ? .orange : .green)
                HStack {
                    Text(friendlyBudgetMessage(progress: progress))
                    Spacer()
                    Text("Plan: \(budget.formatted(.currency(code: currencyCode)))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color.green.opacity(0.14), Color.blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var categoryBreakdown: some View {
        let groups = Dictionary(grouping: monthlyExpenses, by: { SimpleExpenseCategory.category(for: $0.title) })
        let totals = groups.map { category, entries in
            ExpenseCategoryTotal(category: category, amount: entries.compactMap(\.amount).reduce(0, +))
        }.sorted { $0.amount > $1.amount }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Where it went")
                .font(.title2.bold())
            Text("Simple groups based on what you wrote. No bookkeeping required.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(totals) { total in
                BarMark(x: .value("Amount", total.amount), y: .value("Category", total.category.title))
                    .foregroundStyle(total.category.color.gradient)
                    .cornerRadius(5)
            }
            .chartXAxis { AxisMarks(format: Decimal.FormatStyle.Currency(code: currencyCode).precision(.fractionLength(0))) }
            .frame(height: CGFloat(max(totals.count, 3) * 42))
        }
        .padding(18)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var recentExpenses: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent spending")
                .font(.title2.bold())
            ForEach(monthlyExpenses.sorted { $0.timestamp > $1.timestamp }.prefix(12)) { entry in
                HStack(spacing: 12) {
                    let category = SimpleExpenseCategory.category(for: entry.title)
                    Image(systemName: category.icon)
                        .foregroundStyle(category.color)
                        .frame(width: 36, height: 36)
                        .background(category.color.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.subheadline.weight(.semibold))
                        Text(entry.timestamp, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((entry.amount ?? 0).formatted(.currency(code: currencyCode)))
                        .font(.subheadline.bold())
                }
                Divider()
            }
        }
    }

    private var savingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                title: "Saving plans",
                subtitle: "Choose something you want, set a target, then add money whenever you can.",
                button: "New goal",
                action: { showingSavingPlan = true }
            )
            if finance.savingPlans.isEmpty {
                friendlyEmpty(title: "Nothing to save for yet", message: "Try a laptop, emergency cushion, course, or holiday.", icon: "target") {
                    showingSavingPlan = true
                }
            } else {
                ForEach(finance.savingPlans) { plan in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.name).font(.title3.bold())
                                Text("\(plan.savedAmount.formatted(.currency(code: currencyCode))) saved of \(plan.targetAmount.formatted(.currency(code: currencyCode)))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add money") { contributionPlan = plan }
                                .buttonStyle(.borderedProminent)
                        }
                        ProgressView(value: plan.progress).tint(.green)
                        HStack {
                            Text(plan.progress, format: .percent.precision(.fractionLength(0)))
                            Spacer()
                            if let date = plan.targetDate { Text("Target: \(date.formatted(date: .abbreviated, time: .omitted))") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }

    private var tripsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                title: "Trip budgets",
                subtitle: "Plan the total first, then record each trip expense as it happens.",
                button: "Plan a trip",
                action: { showingTrip = true }
            )
            if finance.trips.isEmpty {
                friendlyEmpty(title: "No trip planned", message: "Create a simple budget before you travel.", icon: "airplane") {
                    showingTrip = true
                }
            } else {
                ForEach(finance.trips) { trip in
                    tripCard(trip)
                }
            }
        }
    }

    private func tripCard(_ trip: TripBudgetPlan) -> some View {
        let entries = model.entries.filter { trip.expenseEntryIDs.contains($0.id) }
        let spent = entries.compactMap(\.amount).reduce(0, +)
        let left = trip.budget - spent
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.name).font(.title3.bold())
                    Label(trip.destination, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add trip expense") {
                    expenseTripID = trip.id
                    showingExpense = true
                }
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 20) {
                moneyMetric("Spent", spent)
                moneyMetric(left >= 0 ? "Left" : "Over", abs(left))
                moneyMetric("Total plan", trip.budget)
            }
            ProgressView(value: trip.budget <= 0 ? 0 : min(spent / trip.budget, 1))
                .tint(left >= 0 ? .blue : .red)
            Text("\(trip.startDate.formatted(date: .abbreviated, time: .omitted)) – \(trip.endDate.formatted(date: .abbreviated, time: .omitted)) · \(entries.count) expenses")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func moneyMetric(_ title: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(amount.formatted(.currency(code: currencyCode))).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeading(title: String, subtitle: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button(button, action: action).buttonStyle(.borderedProminent)
        }
    }

    private func friendlyEmpty(title: String, message: String, icon: String, action: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            Button("Get started", action: action).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func moveMonth(_ value: Int) {
        if let date = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) { selectedMonth = date }
    }

    private func friendlyBudgetMessage(progress: Double) -> String {
        if progress > 1 { return "You passed the plan. Review the largest groups—no guilt, just information." }
        if progress > 0.8 { return "Most of the plan is used. Check what remains before the next purchase." }
        if progress > 0.5 { return "You are over halfway through the plan." }
        return "You have plenty of room left in the plan."
    }

    private var currentDeviceSource: DeviceSource {
#if os(macOS)
        .mac
#else
        .phone
#endif
    }
}

private enum MoneySection: String, CaseIterable, Identifiable {
    case month, savings, trips
    var id: Self { self }
    var title: String { self == .month ? "This month" : self == .savings ? "Savings" : "Trips" }
    var icon: String { self == .month ? "chart.bar" : self == .savings ? "target" : "airplane" }
}

private enum SimpleExpenseCategory: String, CaseIterable, Identifiable {
    case food, transport, shopping, fun, bills, travel, other
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self { case .food: "fork.knife"; case .transport: "bus"; case .shopping: "bag"; case .fun: "gamecontroller"; case .bills: "doc.text"; case .travel: "airplane"; case .other: "square.grid.2x2" }
    }
    var color: Color {
        switch self { case .food: .orange; case .transport: .blue; case .shopping: .pink; case .fun: .purple; case .bills: .red; case .travel: .cyan; case .other: .gray }
    }
    static func category(for title: String) -> Self {
        let value = title.lowercased()
        if ["food", "lunch", "dinner", "breakfast", "coffee", "grocery", "restaurant"].contains(where: value.contains) { return .food }
        if ["bus", "train", "fuel", "taxi", "uber", "transport", "parking"].contains(where: value.contains) { return .transport }
        if ["rent", "bill", "electric", "internet", "insurance", "phone"].contains(where: value.contains) { return .bills }
        if ["trip", "hotel", "flight", "holiday", "travel"].contains(where: value.contains) { return .travel }
        if ["movie", "game", "concert", "party", "fun"].contains(where: value.contains) { return .fun }
        if ["bought", "buy", "shopping", "clothes", "amazon"].contains(where: value.contains) { return .shopping }
        return .other
    }
}

private struct ExpenseCategoryTotal: Identifiable {
    var id: SimpleExpenseCategory { category }
    let category: SimpleExpenseCategory
    let amount: Double
}

private struct MonthlyBudgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    let onSave: (Double?) -> Void
    init(current: Double?, onSave: @escaping (Double?) -> Void) {
        _amount = State(initialValue: current.map { String(format: "%.2f", $0) } ?? "")
        self.onSave = onSave
    }
    var body: some View {
        MoneyFormShell(title: "Monthly spending plan", explanation: "Choose an amount you feel comfortable spending this month. You can change it anytime.") {
            TextField("Example: 800", text: $amount)
        } save: {
            onSave(Double(amount.replacingOccurrences(of: ",", with: ".")))
            dismiss()
        }
    }
}

private struct AddExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trip: TripBudgetPlan?
    let onSave: (String, Double, Date) -> Void
    @State private var title = ""
    @State private var amount = ""
    @State private var date = Date.now
    var body: some View {
        MoneyFormShell(title: trip.map { "\($0.name) expense" } ?? "Add expense", explanation: "Write what you paid for in everyday words.") {
            TextField("What did you buy?", text: $title)
            TextField("Amount", text: $amount)
            DatePicker("When", selection: $date)
        } save: {
            guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
            onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), value, date)
            dismiss()
        }
    }
}

private struct NewSavingPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, Double, Date?) -> Void
    @State private var name = ""
    @State private var amount = ""
    @State private var hasDate = false
    @State private var date = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    var body: some View {
        MoneyFormShell(title: "New saving goal", explanation: "Start with what you want and how much it costs. Small contributions still count.") {
            TextField("What are you saving for?", text: $name)
            TextField("Target amount", text: $amount)
            Toggle("I have a target date", isOn: $hasDate)
            if hasDate { DatePicker("Target date", selection: $date, displayedComponents: .date) }
        } save: {
            guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
            onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), value, hasDate ? date : nil)
            dismiss()
        }
    }
}

private struct SavingContributionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: SavingPlan
    let onSave: (Double, String) -> Void
    @State private var amount = ""
    @State private var note = ""
    var body: some View {
        MoneyFormShell(title: "Add money to \(plan.name)", explanation: "This records progress toward the goal. It is not counted as an expense.") {
            TextField("Amount saved", text: $amount)
            TextField("Optional note", text: $note)
        } save: {
            guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
            onSave(value, note)
            dismiss()
        }
    }
}

private struct NewTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (TripBudgetPlan) -> Void
    @State private var name = ""
    @State private var destination = ""
    @State private var budget = ""
    @State private var start = Date.now
    @State private var end = Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now
    var body: some View {
        MoneyFormShell(title: "Plan a trip", explanation: "Set one total amount first. Sakhya will show how much remains as you spend.") {
            TextField("Trip name", text: $name)
            TextField("Destination", text: $destination)
            TextField("Total budget", text: $budget)
            DatePicker("Starts", selection: $start, displayedComponents: .date)
            DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
        } save: {
            guard let value = Double(budget.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
            onSave(TripBudgetPlan(name: name, destination: destination, budget: value, startDate: start, endDate: end))
            dismiss()
        }
    }
}

private struct MoneyFormShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let explanation: String
    @ViewBuilder let content: Content
    let save: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section { content } footer: { Text(explanation) }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .frame(minWidth: 390, minHeight: 330)
    }
}
