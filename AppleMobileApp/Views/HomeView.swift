import PhotosUI
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDate = Date.now
    @State private var showingAddEntry = false
    @State private var quickInput = ""
    @State private var detailsDraft = ""
    @State private var calendarExpanded = false
    @FocusState private var quickCaptureFocused: Bool

    private var entries: [LogEntry] { model.entries(on: selectedDate) }
    private var quickSuggestion: SmartCapture { SmartCapture(text: quickInput) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dateHeader
                quickCapture
                summary
                timeline
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Calendar.current.isDateInToday(selectedDate) ? "Today" : selectedDate.formatted(date: .abbreviated, time: .omitted))
        .sheet(isPresented: $showingAddEntry) {
            AddEntryView(defaultDate: selectedDate, initialText: detailsDraft) {
                quickInput = ""
            }
                .environment(model)
        }
#if os(macOS)
        .onAppear { quickCaptureFocused = true }
#endif
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick capture", systemImage: "sparkles")
                .font(.headline)

            TextField(
                "Log anything — “walked 30 minutes”, “spent €18”, or “remind me tomorrow at 6pm”…",
                text: $quickInput,
                axis: .vertical
            )
            .lineLimit(2...5)
            .font(.title3)
            .textFieldStyle(.plain)
            .focused($quickCaptureFocused)
            .onSubmit(addQuickEntry)

            Divider()

            HStack(spacing: 12) {
                Label(quickSuggestion.category.displayName, systemImage: quickSuggestion.category.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let kind = quickSuggestion.listKind,
                   let list = model.suggestedList(for: quickInput, kind: kind) {
                    Label(list.name, systemImage: list.access.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(list.access == .shared ? .blue : .secondary)
                }

                Spacer()

                Button("More details") {
                    detailsDraft = quickInput
                    showingAddEntry = true
                }
                .buttonStyle(.borderless)

                Button("Add", action: addQuickEntry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func addQuickEntry() {
        guard !quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.addCapturedText(quickInput, on: selectedDate)
        quickInput = ""
        quickCaptureFocused = true
    }

    private var dateHeader: some View {
        ElegantCalendar(selectedDate: $selectedDate, isExpanded: $calendarExpanded)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            SummaryCard(
                title: "Entries",
                value: "\(entries.count)",
                icon: "list.bullet",
                color: .blue
            )
            SummaryCard(
                title: "Spent",
                value: model.expense(on: selectedDate).formatted(.currency(code: currencyCode)),
                icon: "creditcard",
                color: .orange
            )
            SummaryCard(
                title: "Active",
                value: "\(model.activeMinutes(on: selectedDate)) min",
                icon: "figure.walk",
                color: .green
            )
        }
    }

    @ViewBuilder
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Timeline")
                .font(.title2.bold())

            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing logged", systemImage: "clock")
                } description: {
                    Text("Add the first moment from this day.")
                } actions: {
                    Button("Start typing") { quickCaptureFocused = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ForEach(entries) { entry in
                    TimelineRow(entry: entry, attachmentData: model.attachmentData(for: entry)) {
                        model.delete(entry)
                    }
                }
            }
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }
}

private struct ElegantCalendar: View {
    @Binding var selectedDate: Date
    @Binding var isExpanded: Bool
    @State private var displayedMonth = Date.now

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    displayedMonth = monthStart(for: selectedDate)
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.isDateInToday(selectedDate) ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide)))
                                .font(.headline)
                            Text(selectedDate.formatted(.dateTime.day().month(.wide).year()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Close calendar" : "Open calendar")

                Spacer()

                if !calendar.isDateInToday(selectedDate) {
                    Button("Today") { select(.now) }
                        .buttonStyle(.borderless)
                }

                Button {
                    displayedMonth = monthStart(for: selectedDate)
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Close calendar" : "Open calendar")
            }

            weekStrip

            if isExpanded {
                Divider()
                monthGrid
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { date in
                let selected = calendar.isDate(date, inSameDayAs: selectedDate)
                let future = date > calendar.startOfDay(for: .now)

                Button {
                    select(date)
                } label: {
                    VStack(spacing: 7) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selected ? .primary : .secondary)
                        Text(date.formatted(.dateTime.day()))
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(selected ? Color.primary : .clear, in: Circle())
                            .foregroundStyle(selected ? selectedForeground : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(future)
                .opacity(future ? 0.35 : 1)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()

                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveForward)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        monthDay(date)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
    }

    private func monthDay(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(date)
        let future = date > calendar.startOfDay(for: .now)

        return Button {
            select(date)
            withAnimation(.snappy) { isExpanded = false }
        } label: {
            Text(date.formatted(.dateTime.day()))
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(selected ? Color.primary : .clear, in: Circle())
                .foregroundStyle(selected ? selectedForeground : .primary)
                .overlay {
                    if today && !selected {
                        Circle().stroke(Color.blue, lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(future)
        .opacity(future ? 0.28 : 1)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var weekDates: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
            ?? calendar.startOfDay(for: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthDays: [Date?] {
        let start = monthStart(for: displayedMonth)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let blanks = Array<Date?>(repeating: nil, count: leading)
        let days = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        }
        return blanks + days.map(Optional.some)
    }

    private var canMoveForward: Bool {
        monthStart(for: displayedMonth) < monthStart(for: .now)
    }

    private var selectedForeground: Color {
#if os(macOS)
        Color(NSColor.windowBackgroundColor)
#else
        Color(UIColor.systemBackground)
#endif
    }

    private func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func shiftMonth(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = monthStart(for: min(next, .now))
    }

    private func select(_ date: Date) {
        selectedDate = min(date, .now)
        displayedMonth = monthStart(for: selectedDate)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TimelineRow: View {
    let entry: LogEntry
    let attachmentData: Data?
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 5) {
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: entry.category.systemImage)
                    .font(.headline)
                    .foregroundStyle(categoryColor)
                    .frame(width: 36, height: 36)
                    .background(categoryColor.opacity(0.14), in: Circle())
            }
            .frame(width: 58)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entry.title)
                        .font(.headline)
                    Spacer()
                    if let amount = entry.amount {
                        Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "EUR"))
                            .font(.subheadline.bold())
                    }
                    if let minutes = entry.durationMinutes {
                        Text("\(minutes) min")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 8) {
                    Text(entry.category.displayName)
                    if let status = entry.status {
                        Text(status.rawValue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.12), in: Capsule())
                    }
                }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(categoryColor)

                if entry.lifeArea != nil || entry.deviceSource != nil {
                    HStack(spacing: 12) {
                        if let area = entry.lifeArea {
                            Label(area.rawValue, systemImage: area.systemImage)
                        }
                        if let device = entry.deviceSource {
                            Label(device.rawValue, systemImage: device.systemImage)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let source = entry.fitnessSource {
                    Label(source, systemImage: "heart.text.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let listKind = entry.listKind {
                    HStack(spacing: 10) {
                        Label(listKind.displayName, systemImage: listKind.systemImage)
                        if let dueDate = entry.dueDate {
                            Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        }
                        if entry.appleReminderIdentifier != nil {
                            Label("Apple Reminders", systemImage: "checkmark.icloud")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let attachmentData {
                    AttachmentImage(data: attachmentData)
                        .frame(maxWidth: 420, minHeight: 120, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 5)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .contextMenu {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }

    private var categoryColor: Color {
        switch entry.category {
        case .routine: .yellow
        case .work: .blue
        case .expense: .orange
        case .fitness: .green
        case .sleep: .indigo
        case .food: .pink
        case .mood: .purple
        case .screenTime: .cyan
        case .list: .mint
        case .book: .indigo
        case .movie: .red
        case .journal: .teal
        case .idea: .yellow
        case .note: .gray
        }
    }
}

private struct AttachmentImage: View {
    let data: Data

    var body: some View {
#if os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        }
#else
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
#endif
    }
}

private struct AddEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var input: String
    @State private var selectedCategory: LogCategory?
    @State private var note = ""
    @State private var timestamp: Date
    @State private var amount = ""
    @State private var duration = ""
    @State private var status: EntryStatus = .inProgress
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var selectedLifeArea: LifeArea?
    @State private var selectedDevice: DeviceSource?
    @State private var selectedListKind: ListKind?
    @State private var selectedListID: UUID?
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    private let onSaved: () -> Void

    private var suggestion: SmartCapture { SmartCapture(text: input) }
    private var category: LogCategory { selectedCategory ?? suggestion.category }
    private var lifeArea: LifeArea { selectedLifeArea ?? suggestion.lifeArea }
    private var deviceSource: DeviceSource? { selectedDevice ?? suggestion.deviceSource }
    private var listKind: ListKind { selectedListKind ?? suggestion.listKind ?? .task }
    private var destinationList: SakhyaList? {
        model.list(withID: selectedListID) ?? model.suggestedList(for: input, kind: listKind)
    }

    init(defaultDate: Date, initialText: String = "", onSaved: @escaping () -> Void = {}) {
        _input = State(initialValue: initialText)
        self.onSaved = onSaved
        let calendar = Calendar.current
        if calendar.isDateInToday(defaultDate) {
            _timestamp = State(initialValue: .now)
        } else {
            let components = calendar.dateComponents([.hour, .minute], from: .now)
            _timestamp = State(initialValue: calendar.date(bySettingHour: components.hour ?? 12, minute: components.minute ?? 0, second: 0, of: defaultDate) ?? defaultDate)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Log anything…", text: $input, axis: .vertical)
                        .lineLimit(4...9)
                        .font(.body)

                    HStack {
                        Label("Suggested", systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Category", selection: Binding(
                            get: { category },
                            set: { selectedCategory = $0 }
                        )) {
                            ForEach(LogCategory.allCases) { category in
                                Label(category.displayName, systemImage: category.systemImage)
                                    .tag(category)
                            }
                        }
                        .labelsHidden()
                    }

                    DatePicker("When", selection: $timestamp)
                } header: {
                    Text("What happened?")
                } footer: {
                    Text("Try “walked 30 minutes”, “spent €18 on groceries”, or “want to read Dune”. You can always change the category.")
                }

                if category == .expense {
                    Section("Expense") {
                        TextField("Amount", text: $amount, prompt: suggestion.amount.map { Text($0.formatted()) })
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                    }
                }

                if category == .fitness || category == .sleep || category == .work || category == .screenTime || category == .routine {
                    Section(category == .screenTime ? "Screen time" : "Time tracked") {
                        TextField("Duration in minutes", text: $duration, prompt: suggestion.durationMinutes.map { Text("\($0)") })
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                    }
                }

                Section("Work-life context") {
                    Picker("Area", selection: Binding(
                        get: { lifeArea },
                        set: { selectedLifeArea = $0 }
                    )) {
                        ForEach(LifeArea.allCases) { area in
                            Label(area.rawValue, systemImage: area.systemImage).tag(area)
                        }
                    }

                    Picker("Device", selection: Binding(
                        get: { deviceSource },
                        set: { selectedDevice = $0 }
                    )) {
                        Text("Not specified").tag(DeviceSource?.none)
                        ForEach(DeviceSource.allCases) { device in
                            Label(device.rawValue, systemImage: device.systemImage)
                                .tag(DeviceSource?.some(device))
                        }
                    }
                }

                if category == .book || category == .movie {
                    Section(category == .book ? "Reading status" : "Watching status") {
                        Picker("Status", selection: $status) {
                            ForEach(EntryStatus.allCases) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if category == .list {
                    Section("Save to list") {
                        Picker("List", selection: Binding(
                            get: { destinationList?.id },
                            set: { id in
                                selectedListID = id
                                if let list = model.list(withID: id) {
                                    selectedListKind = list.kind
                                }
                            }
                        )) {
                            ForEach(model.lists) { list in
                                Label(list.name, systemImage: list.access.systemImage)
                                    .tag(Optional(list.id))
                            }
                        }

                        if destinationList?.access == .shared {
                            Label("Everyone with edit access will see this item.", systemImage: "person.2.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("Remind me", isOn: $hasDueDate)
                        if hasDueDate {
                            DatePicker("Date and time", selection: $dueDate)
                        }
                    }
                }

                Section("Journal details") {
                    TextField("Optional reflection or details", text: $note, axis: .vertical)
                        .lineLimit(3...8)

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoData == nil ? "Attach photo" : "Change photo", systemImage: "photo")
                    }

                    if let photoData {
                        AttachmentImage(data: photoData)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: suggestion.status) { _, suggestedStatus in
                if let suggestedStatus { status = suggestedStatus }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    photoData = try? await newItem?.loadTransferable(type: Data.self)
                }
            }
            .onChange(of: suggestion.dueDate) { _, suggestedDate in
                if let suggestedDate {
                    dueDate = suggestedDate
                    hasDueDate = true
                }
            }
            .onAppear {
                if let suggestedStatus = suggestion.status { status = suggestedStatus }
                if let suggestedDate = suggestion.dueDate {
                    dueDate = suggestedDate
                    hasDueDate = true
                }
            }
        }
        .frame(minWidth: 360, minHeight: 480)
    }

    private func save() {
        let normalizedAmount = amount.replacingOccurrences(of: ",", with: ".")
        let typedAmount = Double(normalizedAmount)
        model.add(LogEntry(
            timestamp: timestamp,
            category: category,
            title: input.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: category == .expense ? (typedAmount ?? suggestion.amount) : nil,
            durationMinutes: Int(duration) ?? suggestion.durationMinutes,
            status: (category == .book || category == .movie) ? status : nil,
            lifeArea: lifeArea,
            deviceSource: deviceSource,
            listKind: category == .list ? destinationList?.kind ?? listKind : nil,
            listID: category == .list ? destinationList?.id : nil,
            dueDate: category == .list && hasDueDate ? dueDate : nil
        ), photoData: photoData)
        onSaved()
        dismiss()
    }
}
