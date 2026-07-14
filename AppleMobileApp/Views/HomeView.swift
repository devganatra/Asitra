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

    private var entries: [LogEntry] { model.entries(on: selectedDate) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dateHeader
                summary
                timeline
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Calendar.current.isDateInToday(selectedDate) ? "Today" : selectedDate.formatted(date: .abbreviated, time: .omitted))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddEntry = true
                } label: {
                    Label("Add entry", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddEntryView(defaultDate: selectedDate)
                .environment(model)
        }
    }

    private var dateHeader: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }

            DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDateInToday(selectedDate))

            Spacer()

            if !Calendar.current.isDateInToday(selectedDate) {
                Button("Today") { selectedDate = .now }
            }
        }
        .buttonStyle(.bordered)
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
                    Button("Add entry") { showingAddEntry = true }
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

    @State private var input = ""
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
    @State private var hasDueDate = false
    @State private var dueDate = Date.now

    private var suggestion: SmartCapture { SmartCapture(text: input) }
    private var category: LogCategory { selectedCategory ?? suggestion.category }
    private var lifeArea: LifeArea { selectedLifeArea ?? suggestion.lifeArea }
    private var deviceSource: DeviceSource? { selectedDevice ?? suggestion.deviceSource }
    private var listKind: ListKind { selectedListKind ?? suggestion.listKind ?? .task }

    init(defaultDate: Date) {
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
                            get: { listKind },
                            set: { selectedListKind = $0 }
                        )) {
                            ForEach(ListKind.allCases) { kind in
                                Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                            }
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
            listKind: category == .list ? listKind : nil,
            dueDate: category == .list && hasDueDate ? dueDate : nil
        ), photoData: photoData)
        dismiss()
    }
}
