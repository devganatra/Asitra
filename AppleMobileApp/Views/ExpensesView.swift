import Charts
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ExpensesView: View {
    @Environment(AppModel.self) private var model
    @Environment(SystemFeatureModel.self) private var systemFeature
    @State private var section: MoneySection = .overview
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var showingBudget = false
    @State private var showingExpense = false
    @State private var expenseTripID: UUID?
    @State private var showingSavingPlan = false
    @State private var contributionPlan: SavingPlan?
    @State private var showingTrip = false
    @State private var showingWalletRequirements = false
    @State private var moneyEntryKind: PersonalFinanceEntryKind?
    @State private var balanceSheetDraft: BalanceSheetItem?
    @State private var importingStatement = false
    @State private var statementImport: StatementImportDraft?
    @State private var statementImportError: String?

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
    private var walletExpenses: [LogEntry] {
        monthlyExpenses.filter { $0.financialAccountID != nil }
    }
    private var monthlyIncome: Double {
        finance.moneyEntries
            .filter { $0.kind == .income && monthInterval.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
    }
    private var monthlyInvested: Double {
        finance.moneyEntries
            .filter { $0.kind == .investment && monthInterval.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
    }
    private var monthlySaved: Double {
        finance.savingPlans
            .flatMap(\.contributions)
            .filter { monthInterval.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
    }
    private var assets: [BalanceSheetItem] { finance.balanceSheetItems.filter(\.category.isAsset) }
    private var liabilities: [BalanceSheetItem] { finance.balanceSheetItems.filter { !$0.category.isAsset } }
    private var totalAssets: Double { assets.reduce(0) { $0 + $1.balance } }
    private var totalLiabilities: Double { liabilities.reduce(0) { $0 + $1.balance } }
    private var netWorth: Double { totalAssets - totalLiabilities }

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
                    case .overview: positionOverview
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
        .sheet(item: $moneyEntryKind) { kind in
            AddMoneyEntrySheet(kind: kind) { amount, date, note in
                systemFeature.addMoneyEntry(kind: kind, amount: amount, date: date, note: note)
            }
        }
        .sheet(item: $balanceSheetDraft) { draft in
            BalanceSheetItemSheet(item: draft) { systemFeature.upsertBalanceSheetItem($0) }
        }
        .sheet(item: $statementImport) { draft in
            StatementImportReviewSheet(draft: draft) { transactions in
                importStatementTransactions(transactions)
            }
        }
        .fileImporter(isPresented: $importingStatement, allowedContentTypes: [.pdf]) { result in
            readStatement(result)
        }
        .alert("Apple Wallet connection", isPresented: $showingWalletRequirements) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sakhya uses Apple FinanceKit—not unrestricted Apple Pay history. It works on supported iPhones after Apple grants Sakhya the managed FinanceKit entitlement, and you choose which eligible Wallet accounts and date range to share.")
        }
        .alert(
            "Statement could not be imported",
            isPresented: Binding(
                get: { statementImportError != nil },
                set: { if !$0 { statementImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { statementImportError = nil }
        } message: {
            Text(statementImportError ?? "Try a text-based bank statement PDF.")
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
                importingStatement = true
            } label: {
                Label("Import PDF", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
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

    private func readStatement(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let transactions = try StatementPDFParser.parse(url: url)
            guard !transactions.isEmpty else {
                throw StatementImportError.noTransactions
            }
            statementImport = StatementImportDraft(fileName: url.lastPathComponent, transactions: transactions)
        } catch {
            statementImportError = error.localizedDescription
        }
    }

    private func importStatementTransactions(_ transactions: [ImportedStatementTransaction]) {
        let expenseKeys = Set(model.entries.compactMap { entry -> String? in
            guard entry.category == .expense, let amount = entry.amount else { return nil }
            return StatementPDFParser.fingerprint(
                date: entry.timestamp,
                kind: .expense,
                amount: amount,
                title: entry.title
            )
        })
        let incomeKeys = Set(finance.moneyEntries.compactMap { entry -> String? in
            guard entry.kind == .income else { return nil }
            return StatementPDFParser.fingerprint(
                date: entry.date,
                kind: .income,
                amount: entry.amount,
                title: entry.note
            )
        })

        for transaction in transactions where transaction.isSelected {
            let key = StatementPDFParser.fingerprint(
                date: transaction.date,
                kind: transaction.kind,
                amount: transaction.amount,
                title: transaction.title
            )
            switch transaction.kind {
            case .expense where !expenseKeys.contains(key):
                model.add(
                    LogEntry(
                        timestamp: transaction.date,
                        category: .expense,
                        title: transaction.title,
                        note: "Imported from PDF statement",
                        amount: transaction.amount,
                        lifeArea: .personal,
                        deviceSource: currentDeviceSource
                    ),
                    syncToCalendar: false
                )
            case .income where !incomeKeys.contains(key):
                systemFeature.addMoneyEntry(
                    kind: .income,
                    amount: transaction.amount,
                    date: transaction.date,
                    note: transaction.title
                )
            default:
                break
            }
        }
    }

    private var positionOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            monthSelector
            netWorthHero
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                cashFlowCard
                personalProfitLossCard
                balanceSheetCard
            }
            Text("This is a personal overview, not formal accounting or financial advice. Account balances are snapshots; saving goals are allocations and are only assets when the money is also recorded in an account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var netWorthHero: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR MONEY POSITION")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(netWorth.formatted(.currency(code: currencyCode)))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(finance.balanceSheetItems.isEmpty
                    ? "Add what you own and owe to calculate net worth."
                    : "\(totalAssets.formatted(.currency(code: currencyCode))) owned − \(totalLiabilities.formatted(.currency(code: currencyCode))) owed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                balanceSheetDraft = BalanceSheetItem(name: "", balance: 0, category: .cash)
            } label: {
                Label("Add balance", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.14), Color.green.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var cashFlowCard: some View {
        let netCashMovement = monthlyIncome - monthlySpent - monthlyInvested
        return VStack(alignment: .leading, spacing: 13) {
            statementHeading(
                eyebrow: "Movement",
                title: "Cash flow",
                subtitle: "What came in and what left your usable cash.",
                icon: "arrow.left.arrow.right"
            ) {
                moneyEntryKind = .income
            }
            statementRow("Income", amount: monthlyIncome, sign: .positive)
            statementRow("Everyday spending", amount: monthlySpent, sign: .negative)
            statementRow("Moved to investments", amount: monthlyInvested, sign: .negative)
            Divider()
            statementRow("Net cash movement", amount: netCashMovement, emphasize: true)
            if monthlySaved > 0 {
                Label(
                    "\(monthlySaved.formatted(.currency(code: currencyCode))) earmarked for saving goals stays in cash until it is moved to another account.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack {
                Button("Add income") { moneyEntryKind = .income }
                Button("Add investment") { moneyEntryKind = .investment }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .statementCard()
    }

    private var personalProfitLossCard: some View {
        let surplus = monthlyIncome - monthlySpent
        let assigned = monthlySaved + monthlyInvested
        let remainder = surplus - assigned
        let isBalanced = abs(remainder) < 0.01
        return VStack(alignment: .leading, spacing: 13) {
            statementHeading(
                eyebrow: "Zero-based allocation",
                title: "Personal P&L",
                subtitle: "Give every euro of your monthly surplus a purpose.",
                icon: "equal.circle"
            )
            statementRow("Income", amount: monthlyIncome)
            statementRow("Spent on life", amount: monthlySpent, sign: .negative)
            statementRow("Surplus after spending", amount: surplus, emphasize: true)
            Divider()
            statementRow("Saved", amount: monthlySaved)
            statementRow("Invested", amount: monthlyInvested)
            statementRow(
                remainder >= 0 ? "Still to assign" : "Used from reserves",
                amount: abs(remainder),
                emphasize: true
            )
            Label(
                isBalanced ? "Balanced: income has been fully spent, saved or invested." :
                    remainder > 0 ? "Assign the remainder to a saving goal or investment to reach zero." :
                    "Spending and allocations exceed this month’s income; the difference came from existing cash or debt.",
                systemImage: isBalanced ? "checkmark.circle.fill" : "lightbulb"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(isBalanced ? .green : remainder > 0 ? .orange : .red)
            Text("Unlike a business P&L, saving and investing are shown as uses of personal surplus—not expenses.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .statementCard()
    }

    private var balanceSheetCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            statementHeading(
                eyebrow: "Snapshot",
                title: "Balance sheet",
                subtitle: "What you own, what you owe, and the difference.",
                icon: "scale.3d"
            ) {
                balanceSheetDraft = BalanceSheetItem(name: "", balance: 0, category: .cash)
            }
            if finance.balanceSheetItems.isEmpty {
                Text("Start with bank balances, investments, credit cards and loans. Update them whenever a statement changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("ASSETS")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                ForEach(assets.sorted { $0.balance > $1.balance }) { item in
                    balanceItemRow(item)
                }
                statementRow("Total assets", amount: totalAssets, emphasize: true)
                Divider()
                Text("LIABILITIES")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                ForEach(liabilities.sorted { $0.balance > $1.balance }) { item in
                    balanceItemRow(item)
                }
                statementRow("Total liabilities", amount: totalLiabilities, emphasize: true)
                Divider()
                statementRow("Net worth", amount: netWorth, emphasize: true)
            }
            Button {
                balanceSheetDraft = BalanceSheetItem(name: "", balance: 0, category: .cash)
            } label: {
                Label("Add asset or debt", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .statementCard()
    }

    private func balanceItemRow(_ item: BalanceSheetItem) -> some View {
        Button {
            balanceSheetDraft = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.category.systemImage)
                    .foregroundStyle(item.category.isAsset ? .green : .orange)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                    Text(item.category.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.balance.formatted(.currency(code: currencyCode)))
                    .font(.subheadline.monospacedDigit())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private enum StatementSign {
        case positive, negative
    }

    private func statementRow(
        _ title: String,
        amount: Double,
        sign: StatementSign? = nil,
        emphasize: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(emphasize ? .primary : .secondary)
            Spacer()
            Text(statementAmount(amount, sign: sign))
                .fontWeight(emphasize ? .bold : .semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func statementAmount(_ amount: Double, sign: StatementSign?) -> String {
        let formatted = abs(amount).formatted(.currency(code: currencyCode))
        if amount < 0 { return "−\(formatted)" }
        switch sign {
        case .positive: return "+\(formatted)"
        case .negative: return amount == 0 ? formatted : "−\(formatted)"
        case nil: return formatted
        }
    }

    @ViewBuilder
    private func statementHeading(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.caption2.bold())
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var monthlyView: some View {
        VStack(alignment: .leading, spacing: 18) {
            monthSelector
            walletConnectionCard
            budgetHero
            if !monthlyExpenses.isEmpty {
                if !walletExpenses.isEmpty {
                    cardBreakdown
                }
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

    private var walletConnectionCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "apple.logo")
                .font(.title2.weight(.semibold))
                .frame(width: 46, height: 46)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Wallet spending")
                    .font(.headline)
                Text(model.financialDataStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let lastImport = model.lastFinancialImport {
                    Text("Last checked \(lastImport.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                if model.isFinancialDataAvailable {
                    Task { await model.importAppleWalletSpending() }
                } else {
                    showingWalletRequirements = true
                }
            } label: {
                if model.isImportingFinancialData {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(model.lastFinancialImport == nil ? "Connect" : "Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isImportingFinancialData)

            Button {
                showingWalletRequirements = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apple Wallet requirements")
        }
        .padding(18)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        let groups = Dictionary(grouping: monthlyExpenses, by: SimpleExpenseCategory.category)
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

    private var cardBreakdown: some View {
        let grouped = Dictionary(grouping: walletExpenses) {
            $0.financialAccountID ?? UUID()
        }
        let totals = grouped.compactMap { _, entries -> CardExpenseTotal? in
            guard let first = entries.first else { return nil }
            return CardExpenseTotal(
                id: first.financialAccountID ?? first.id,
                cardName: first.financialAccountName ?? "Wallet account",
                institutionName: first.financialInstitutionName ?? "",
                currencyCode: first.financialCurrencyCode ?? currencyCode,
                amount: entries.compactMap(\.amount).reduce(0, +),
                transactionCount: entries.count
            )
        }.sorted { $0.amount > $1.amount }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Spending by card")
                        .font(.title2.bold())
                    Text("Transactions stay linked to the account Apple Wallet provided.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(walletExpenses.count) imported")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(totals) { total in
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 38, height: 38)
                        .background(Color.blue.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(total.cardName)
                            .font(.subheadline.weight(.semibold))
                        Text([total.institutionName, "\(total.transactionCount) transactions"]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(total.amount.formatted(.currency(code: total.currencyCode)))
                        .font(.headline)
                }
                if total.id != totals.last?.id {
                    Divider()
                }
            }
        }
        .padding(18)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var recentExpenses: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent spending")
                .font(.title2.bold())
            ForEach(monthlyExpenses.sorted { $0.timestamp > $1.timestamp }.prefix(12)) { entry in
                HStack(spacing: 12) {
                    let category = SimpleExpenseCategory.category(for: entry)
                    Image(systemName: category.icon)
                        .foregroundStyle(category.color)
                        .frame(width: 36, height: 36)
                        .background(category.color.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.subheadline.weight(.semibold))
                        Text(entry.timestamp, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        if let card = entry.financialAccountName {
                            Label(card, systemImage: "creditcard")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text((entry.amount ?? 0).formatted(.currency(code: entry.financialCurrencyCode ?? currencyCode)))
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
    case overview, month, savings, trips
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .month: "Spending"
        case .savings: "Goals"
        case .trips: "Trips"
        }
    }
    var icon: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .month: "chart.bar"
        case .savings: "target"
        case .trips: "airplane"
        }
    }
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
    static func category(for entry: LogEntry) -> Self {
        if let code = entry.merchantCategoryCode {
            switch code {
            case 3000...3999, 4511, 4722, 7011, 7512:
                return .travel
            case 4111, 4121, 4131, 4784, 4789, 5541, 5542:
                return .transport
            case 4812...4899, 4900, 6010...6399:
                return .bills
            case 5411, 5422, 5441, 5451, 5462, 5499, 5811...5814:
                return .food
            case 7832, 7911, 7922, 7929, 7932, 7933, 7941, 7991...7999:
                return .fun
            case 5000...5699, 5712, 5732, 5734, 5940...5999:
                return .shopping
            default:
                break
            }
        }
        let value = entry.title.lowercased()
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

private struct CardExpenseTotal: Identifiable {
    let id: UUID
    let cardName: String
    let institutionName: String
    let currencyCode: String
    let amount: Double
    let transactionCount: Int
}

private enum ImportedStatementKind: String, Sendable {
    case expense
    case income
}

private struct ImportedStatementTransaction: Identifiable, Sendable {
    let id: UUID
    let kind: ImportedStatementKind
    let title: String
    let amount: Double
    let date: Date
    var isSelected: Bool
}

private struct StatementImportDraft: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let transactions: [ImportedStatementTransaction]
}

private enum StatementImportError: LocalizedError {
    case unreadablePDF
    case noTransactions

    var errorDescription: String? {
        switch self {
        case .unreadablePDF:
            "This PDF could not be read. Try an original statement rather than a scanned image."
        case .noTransactions:
            "No dated transactions with amounts were found. Try a text-based bank statement PDF."
        }
    }
}

private enum StatementPDFParser {
    private static let datePattern = #"\b(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?\b"#
    private static let amountPattern = #"([+-]?\s*(?:\d{1,3}(?:[.\s]\d{3})*|\d+)[,.]\d{2})\s*(?:€|EUR)?\s*([+-])?"#

    static func parse(url: URL, now: Date = .now) throws -> [ImportedStatementTransaction] {
        guard let document = PDFDocument(url: url), let text = document.string else {
            throw StatementImportError.unreadablePDF
        }
        let dateRegex = try NSRegularExpression(pattern: datePattern)
        let amountRegex = try NSRegularExpression(pattern: amountPattern, options: [.caseInsensitive])
        var transactions: [ImportedStatementTransaction] = []
        var seen = Set<String>()

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  line.range(
                    of: #"\b(opening|closing|available|new)\s+balance\b"#,
                    options: [.regularExpression, .caseInsensitive]
                  ) == nil
            else { continue }

            let range = NSRange(line.startIndex..., in: line)
            guard let dateMatch = dateRegex.firstMatch(in: line, range: range),
                  let date = parseDate(dateMatch, in: line, now: now)
            else { continue }
            let amountMatches = amountRegex.matches(in: line, range: range)
            guard let amountMatch = amountMatches.last,
                  let rawAmountRange = Range(amountMatch.range(at: 1), in: line)
            else { continue }

            let rawAmount = String(line[rawAmountRange])
            guard let amount = localizedAmount(rawAmount), amount > 0, amount <= 1_000_000_000 else {
                continue
            }
            let suffix = amountMatch.range(at: 2).location != NSNotFound
                ? (Range(amountMatch.range(at: 2), in: line).map { String(line[$0]) } ?? "")
                : ""
            let signed = rawAmount.replacingOccurrences(of: " ", with: "") + suffix
            let explicitlyPositive = signed.hasPrefix("+") ||
                line.range(of: #"\bcredit\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            let explicitlyNegative = signed.hasPrefix("-") || signed.hasSuffix("-")
            let kind: ImportedStatementKind = explicitlyPositive && !explicitlyNegative ? .income : .expense

            let dateText = Range(dateMatch.range, in: line).map { String(line[$0]) } ?? ""
            let amountText = Range(amountMatch.range, in: line).map { String(line[$0]) } ?? rawAmount
            let title = line
                .replacingOccurrences(of: dateText, with: "")
                .replacingOccurrences(of: amountText, with: "")
                .replacingOccurrences(of: #"\b(?:EUR|€)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " |:;,-"))
            let safeTitle = String((title.isEmpty ? "Statement transaction" : title).prefix(160))
            let key = fingerprint(date: date, kind: kind, amount: amount, title: safeTitle)
            guard seen.insert(key).inserted else { continue }
            transactions.append(
                ImportedStatementTransaction(
                    id: UUID(),
                    kind: kind,
                    title: safeTitle,
                    amount: amount,
                    date: date,
                    isSelected: true
                )
            )
            if transactions.count == 500 { break }
        }
        return transactions
    }

    static func fingerprint(
        date: Date,
        kind: ImportedStatementKind,
        amount: Double,
        title: String
    ) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "\(day)|\(kind.rawValue)|\(String(format: "%.2f", amount))|\(title.lowercased())"
    }

    private static func parseDate(_ match: NSTextCheckingResult, in line: String, now: Date) -> Date? {
        func number(at index: Int) -> Int? {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: line)
            else { return nil }
            return Int(line[range])
        }
        guard let day = number(at: 1), let month = number(at: 2) else { return nil }
        var year = number(at: 3) ?? Calendar.current.component(.year, from: now)
        if year < 100 { year += year < 70 ? 2_000 : 1_900 }
        if number(at: 3) == nil,
           month > Calendar.current.component(.month, from: now) + 1 {
            year -= 1
        }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    private static func localizedAmount(_ raw: String) -> Double? {
        let compact = raw.replacingOccurrences(of: " ", with: "")
        let comma = compact.lastIndex(of: ",")
        let dot = compact.lastIndex(of: ".")
        let separator: String.Index?
        switch (comma, dot) {
        case let (comma?, dot?):
            separator = comma > dot ? comma : dot
        case let (comma?, nil):
            separator = comma
        case let (nil, dot?):
            separator = dot
        case (nil, nil):
            separator = nil
        }
        guard let separator else { return nil }
        let integer = compact[..<separator].filter { $0.isNumber || $0 == "-" || $0 == "+" }
        let decimal = compact[compact.index(after: separator)...].filter(\.isNumber)
        guard decimal.count == 2 else { return nil }
        return abs(Double("\(integer).\(decimal)") ?? 0)
    }
}

private struct StatementImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transactions: [ImportedStatementTransaction]
    let fileName: String
    let onImport: ([ImportedStatementTransaction]) -> Void

    init(draft: StatementImportDraft, onImport: @escaping ([ImportedStatementTransaction]) -> Void) {
        _transactions = State(initialValue: draft.transactions)
        fileName = draft.fileName
        self.onImport = onImport
    }

    private var selectedCount: Int { transactions.filter(\.isSelected).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($transactions) { $transaction in
                        Toggle(isOn: $transaction.isSelected) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(transaction.title)
                                    Text("\(transaction.date.formatted(date: .abbreviated, time: .omitted)) · \(transaction.kind.rawValue.capitalized)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(transaction.amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR")))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(transaction.kind == .income ? .green : .primary)
                            }
                        }
                    }
                } header: {
                    Text("\(selectedCount) of \(transactions.count) selected")
                } footer: {
                    Text("Review the detected rows. Nothing is saved until you tap Import.")
                }
            }
            .navigationTitle(fileName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(transactions)
                        dismiss()
                    }
                    .disabled(selectedCount == 0)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }
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

private struct AddMoneyEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: PersonalFinanceEntryKind
    let onSave: (Double, Date, String) -> Void
    @State private var amount = ""
    @State private var date = Date.now
    @State private var note = ""

    var body: some View {
        MoneyFormShell(
            title: kind == .income ? "Record income" : "Record investment",
            explanation: kind == .income
                ? "Income is money received this month, such as salary, freelance work or a refund."
                : "Record money moved from cash into an investment. The investment balance itself belongs on the balance sheet."
        ) {
            TextField("Amount", text: $amount)
            TextField(kind == .income ? "Source or note" : "Investment or note", text: $note)
            DatePicker("When", selection: $date, displayedComponents: .date)
        } save: {
            guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
            onSave(value, date, note.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        }
    }
}

private struct BalanceSheetItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: BalanceSheetItem
    @State private var amount: String
    let onSave: (BalanceSheetItem) -> Void

    init(item: BalanceSheetItem, onSave: @escaping (BalanceSheetItem) -> Void) {
        _item = State(initialValue: item)
        _amount = State(initialValue: item.balance > 0 ? String(format: "%.2f", item.balance) : "")
        self.onSave = onSave
    }

    var body: some View {
        MoneyFormShell(
            title: item.name.isEmpty ? "Add asset or debt" : "Update \(item.name)",
            explanation: "Enter the latest balance as a positive number. Assets add to net worth; debts reduce it."
        ) {
            TextField("Name, for example Main bank", text: $item.name)
            Picker("Type", selection: $item.category) {
                Section("What you own") {
                    ForEach(BalanceSheetCategory.allCases.filter(\.isAsset)) { category in
                        Label(category.title, systemImage: category.systemImage).tag(category)
                    }
                }
                Section("What you owe") {
                    ForEach(BalanceSheetCategory.allCases.filter { !$0.isAsset }) { category in
                        Label(category.title, systemImage: category.systemImage).tag(category)
                    }
                }
            }
            TextField("Current balance", text: $amount)
        } save: {
            guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")),
                  value >= 0,
                  !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            item.balance = value
            onSave(item)
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

private extension View {
    func statementCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
