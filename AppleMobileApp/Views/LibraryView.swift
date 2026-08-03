import Charts
import SwiftUI

struct ListsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedListID: UUID?
    @State private var showingNewList = false
    @State private var listToManage: AsitraList?

    private var listEntries: [LogEntry] {
        model.entries.filter {
            $0.category == .list && (selectedListID == nil || $0.listID == selectedListID)
        }
    }

    private var selectedList: AsitraList? { model.list(withID: selectedListID) }
    private var allListEntryCount: Int { model.entries.filter { $0.category == .list }.count }

    private var pending: [LogEntry] { listEntries.filter { !$0.isCompleted } }
    private var completed: [LogEntry] { listEntries.filter { $0.isCompleted } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your lists")
                            .font(.title2.bold())
                        Text("Choose a space without leaving the page")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let selectedList {
                        Button {
                            listToManage = selectedList
                        } label: {
                            Label("Manage", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        showingNewList = true
                    } label: {
                        Label("New list", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ListSelectionCard(
                            title: "All lists",
                            subtitle: "Private and shared",
                            icon: "square.stack.3d.up.fill",
                            count: allListEntryCount,
                            isShared: false,
                            isSelected: selectedListID == nil
                        ) {
                            withAnimation(.snappy) { selectedListID = nil }
                        }

                        ForEach(model.lists) { list in
                            ListSelectionCard(
                                title: list.name,
                                subtitle: list.access.rawValue,
                                icon: list.kind.systemImage,
                                count: model.entries.filter { $0.category == .list && $0.listID == list.id }.count,
                                isShared: list.access == .shared,
                                isSelected: selectedListID == list.id
                            ) {
                                withAnimation(.snappy) { selectedListID = list.id }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
            .padding()

            if let selectedList, selectedList.access == .shared {
                SharedListBanner(list: selectedList) {
                    listToManage = selectedList
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

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
        .sheet(isPresented: $showingNewList) {
            NewListView { id in selectedListID = id }
        }
        .sheet(item: $listToManage, onDismiss: {
            if let selectedListID, model.list(withID: selectedListID) == nil {
                self.selectedListID = nil
            }
        }) { list in
            ManageListView(list: list)
        }
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
                    if let list = model.list(withID: entry.listID) {
                        Label(list.name, systemImage: list.access.systemImage)
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

private struct ListSelectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let count: Int
    let isShared: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                    }
                }
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Text(subtitle)
                        .lineLimit(1)
                    Spacer()
                    Text("\(count)")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .opacity(0.78)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(14)
            .frame(width: 178, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.12))
            }
            .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .clear, radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SharedListBanner: View {
    let list: AsitraList
    let manage: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: list.isCloudConnected ? "person.2.fill" : "icloud.slash")
                .font(.title3)
                .foregroundStyle(list.isCloudConnected ? .blue : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.isCloudConnected ? "Shared with (list.members.count) people" : "Ready for iCloud sharing")
                    .font(.subheadline.bold())
                Text(list.isCloudConnected
                    ? "Changes from everyone appear here and in the timeline."
                    : "Connect Asitra to its CloudKit container before sending invitations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Details", action: manage)
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.orange.opacity(list.isCloudConnected ? 0 : 0.09), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct NewListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ListKind = .shopping
    @State private var access: ListAccess = .privateList
    let onCreated: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("List") {
                    TextField("Name", text: $name, prompt: Text("Weekend shopping"))
                    Picker("Type", selection: $kind) {
                        ForEach(ListKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                }

                Section("Who can see it?") {
                    Picker("Access", selection: $access) {
                        ForEach(ListAccess.allCases) { access in
                            Label(access.rawValue, systemImage: access.systemImage).tag(access)
                        }
                    }
                    .pickerStyle(.segmented)

                    Label(
                        access == .privateList
                            ? "Only you can see and change this list."
                            : "Invite up to three people. Give each person edit or view-only access.",
                        systemImage: access.systemImage
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let fallback = kind.displayName
                        let id = model.createList(name: name.isEmpty ? fallback : name, kind: kind, access: access)
                        onCreated(id)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 390, minHeight: 360)
    }
}

private struct ManageListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AsitraList
    @State private var showingCloudKitNotice = false
    @State private var sharingError: String?
    @State private var isPreparingShare = false

    init(list: AsitraList) {
        _draft = State(initialValue: list)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("List details") {
                    TextField("Name", text: $draft.name)
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ListKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    Picker("Access", selection: $draft.access) {
                        ForEach(ListAccess.allCases) { access in
                            Label(access.rawValue, systemImage: access.systemImage).tag(access)
                        }
                    }
                }

                if draft.access == .shared {
                    Section {
                        LabeledContent("Owner", value: draft.ownerName)
                        ForEach($draft.members) { $member in
                            HStack {
                                Text(member.displayName)
                                Spacer()
                                Picker("Permission", selection: $member.permission) {
                                    ForEach(ListPermission.allCases) { permission in
                                        Text(permission.rawValue).tag(permission)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        Button {
                            guard model.syncEnabled else {
                                showingCloudKitNotice = true
                                return
                            }
                            isPreparingShare = true
                            Task {
                                defer { isPreparingShare = false }
                                do {
                                    try await model.prepareSharing(for: draft)
                                    if let updated = model.list(withID: draft.id) { draft = updated }
                                } catch {
                                    sharingError = error.localizedDescription
                                }
                            }
                        } label: {
                            if isPreparingShare {
                                ProgressView()
                            } else {
                                Label("Invite people with iCloud", systemImage: "person.badge.plus")
                            }
                        }
                        .disabled(draft.members.count >= 3 || isPreparingShare)
                    } header: {
                        Text("People")
                    } footer: {
                        Text("Only this list is shared. Journal entries, health data, expenses, and other lists stay private.")
                    }
                }

                if !draft.isDefault {
                    Section {
                        Button("Delete List", role: .destructive) {
                            model.deleteList(draft)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Manage List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.access == .privateList {
                            draft.members = []
                            draft.cloudShareRecordName = nil
                            draft.collaborationStatus = .preparing
                        }
                        model.updateList(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("iCloud setup required", isPresented: $showingCloudKitNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The collaboration flow is ready, but invitations need Asitra’s CloudKit container and Apple Developer signing to be configured first.")
            }
            .alert("Sharing unavailable", isPresented: Binding(
                get: { sharingError != nil },
                set: { if !$0 { sharingError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sharingError ?? "Please try again.")
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(SystemFeatureModel.self) private var systemFeature
    @State private var family: TrackerFamily = .health
    @State private var selectedTrackerID: UUID?
    @State private var showingCreator = false
    @State private var showingEntry = false

    private var familyTrackers: [TrackerDefinition] {
        systemFeature.trackers.filter { $0.family == family }
    }

    private var displayedFamilies: [TrackerFamily] {
        let customLegacyFamilies = [TrackerFamily.money, .things].filter { legacyFamily in
            systemFeature.trackers.contains { $0.family == legacyFamily && !$0.isStarter }
        }
        return TrackerFamily.everydayCases + customLegacyFamilies
    }

    private var selectedTracker: TrackerDefinition? {
        familyTrackers.first { $0.id == selectedTrackerID } ?? familyTrackers.first
    }

    private func entries(for tracker: TrackerDefinition) -> [LogEntry] {
        model.entries.filter { entry in
            entry.trackerID == tracker.id || (tracker.isStarter && entry.category == tracker.template.category)
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Track what matters")
                            .font(.largeTitle.bold())
                        Text("Health, habits, learning and mindset — without turning life into a spreadsheet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showingCreator = true
                    } label: {
                        Label("New tracker", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(displayedFamilies) { option in
                            Button {
                                withAnimation(.snappy) {
                                    family = option
                                    selectedTrackerID = systemFeature.trackers.first { $0.family == option }?.id
                                }
                            } label: {
                                Label(option.rawValue, systemImage: option.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(height: 40)
                                    .foregroundStyle(family == option ? Color.white : Color.primary)
                                    .background(family == option ? option.color : Color.secondary.opacity(0.09), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)

                Text(family.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if familyTrackers.isEmpty {
                    ContentUnavailableView {
                        Label("No tracker here yet", systemImage: family.systemImage)
                    } description: {
                        Text("Create one and Asitra will offer the right fields automatically.")
                    } actions: {
                        Button("Create tracker") { showingCreator = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 300)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(familyTrackers) { tracker in
                                TrackerCard(
                                    tracker: tracker,
                                    count: entries(for: tracker).count,
                                    isSelected: tracker.id == selectedTracker?.id
                                ) {
                                    withAnimation(.snappy) { selectedTrackerID = tracker.id }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)

                    if let tracker = selectedTracker {
                        TrackerDetail(
                            tracker: tracker,
                            entries: entries(for: tracker),
                            onAdd: { showingEntry = true }
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Track")
        .sheet(isPresented: $showingCreator) {
            TrackerCreator { name, template in
                let tracker = systemFeature.addTracker(name: name, template: template)
                family = tracker.family
                selectedTrackerID = tracker.id
            }
        }
        .sheet(isPresented: $showingEntry) {
            if let tracker = selectedTracker {
                TrackerEntryForm(tracker: tracker)
            }
        }
        .onAppear {
            if selectedTrackerID == nil {
                selectedTrackerID = familyTrackers.first?.id
            }
        }
    }
}

private struct TrackerCard: View {
    let tracker: TrackerDefinition
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: tracker.template.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : tracker.family.color)
                Text(tracker.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(count == 1 ? "1 entry" : "\(count) entries")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(16)
            .frame(width: 180, height: 112, alignment: .leading)
            .background(isSelected ? tracker.family.color : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.1))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TrackerDetail: View {
    let tracker: TrackerDefinition
    let entries: [LogEntry]
    let onAdd: () -> Void

    private var amount: Double { entries.compactMap(\.amount).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tracker.name)
                        .font(.title2.bold())
                    Text(tracker.template.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onAdd) {
                    Label(tracker.template.family == .habits ? "Check in" : "Add entry", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(tracker.family.color)
            }

            if tracker.template.usesAmount, !entries.isEmpty {
                HStack(spacing: 8) {
                    Text(tracker.template == .saving ? "Added" : "Total")
                        .foregroundStyle(.secondary)
                    Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "EUR"))
                        .font(.title3.bold())
                }
            }

            if entries.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: tracker.template.systemImage)
                        .font(.title2)
                        .foregroundStyle(tracker.family.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ready when you are")
                            .font(.headline)
                        Text("Your first entry will also appear on the timeline.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries.prefix(8)) { entry in
                        TrackerEntryRow(entry: entry, color: tracker.family.color)
                        if entry.id != entries.prefix(8).last?.id { Divider() }
                    }
                }
            }
        }
        .padding(22)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct TrackerEntryRow: View {
    let entry: LogEntry
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.completed == true ? "checkmark.circle.fill" : entry.category.systemImage)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.collectionDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    Text(entry.timestamp, format: .dateTime.day().month(.abbreviated).hour().minute())
                    if let status = entry.status { Text(status.rawValue) }
                    if let minutes = entry.durationMinutes { Text("\(minutes) min") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let amount = entry.amount {
                Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "EUR"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 11)
    }
}

private struct TrackerCreator: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, TrackerTemplate) -> Void
    @State private var family: TrackerFamily = .health
    @State private var template: TrackerTemplate = .movement
    @State private var name = ""

    private var templates: [TrackerTemplate] {
        TrackerTemplate.allCases.filter { $0.family == family }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("What do you want to track?")
                            .font(.title2.bold())
                        Text("Money has its own page and tasks belong in Lists. Track is for personal progress.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(TrackerFamily.everydayCases) { option in
                            Button {
                                family = option
                                template = TrackerTemplate.allCases.first { $0.family == option } ?? .movement
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Image(systemName: option.systemImage)
                                        .font(.title3)
                                    Text(option.rawValue).font(.headline)
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(family == option ? Color.white.opacity(0.8) : Color.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .foregroundStyle(family == option ? Color.white : Color.primary)
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
                                .background(family == option ? option.color : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose a type")
                            .font(.headline)
                        ForEach(templates) { option in
                            Button {
                                template = option
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: option.systemImage)
                                        .foregroundStyle(family.color)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.rawValue).font(.subheadline.weight(.semibold))
                                        Text(option.prompt).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: template == option ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(template == option ? family.color : Color.secondary)
                                }
                                .contentShape(Rectangle())
                                .padding(12)
                                .background(template == option ? family.color.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField("Name (for example: European novels)", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(22)
            }
            .navigationTitle("New tracker")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, template)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 620)
    }
}

private struct TrackerEntryForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let tracker: TrackerDefinition
    @State private var title = ""
    @State private var note = ""
    @State private var amount = 0.0
    @State private var status: EntryStatus = .planned
    @State private var duration = 15
    @State private var dueDate = Date.now
    @State private var hasDueDate = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(titlePrompt, text: $title)
                    if tracker.template.usesAmount {
                        TextField("Amount", value: $amount, format: .number)
                    }
                    if tracker.template.usesStatus {
                        Picker("Status", selection: $status) {
                            ForEach(EntryStatus.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    if tracker.template.usesDuration {
                        Stepper("\(duration) minutes", value: $duration, in: 1...480, step: 5)
                    }
                    if tracker.template.usesDueDate {
                        Toggle("Add a date", isOn: $hasDueDate)
                        if hasDueDate { DatePicker("When", selection: $dueDate) }
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical)
                } header: {
                    Label(tracker.name, systemImage: tracker.template.systemImage)
                } footer: {
                    Text("This entry will also appear on your timeline.")
                }
            }
            .navigationTitle(tracker.template.family == .habits ? "Habit check-in" : "Add entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (tracker.template.usesAmount && amount <= 0))
                }
            }
        }
        .frame(minWidth: 380, minHeight: 390)
    }

    private var titlePrompt: String {
        switch tracker.template.family {
        case .money: tracker.template == .saving ? "What are you saving for?" : "What was it for?"
        case .booksMedia: "Title"
        case .habits: "What did you do?"
        case .things: "What is it?"
        case .health: "What would you like to record?"
        case .mindset: "What is on your mind?"
        }
    }

    private func save() {
        let listKind: ListKind? = switch tracker.template {
        case .wishlist: .shopping
        case .reminders: .reminder
        case .checklist: .task
        default: nil
        }
        let entry = LogEntry(
            timestamp: .now,
            category: tracker.template.category,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: tracker.template.usesAmount ? amount : nil,
            durationMinutes: tracker.template.usesDuration ? duration : nil,
            status: tracker.template.usesStatus ? status : nil,
            lifeArea: .personal,
            deviceSource: model.currentDeviceSource,
            listKind: listKind,
            dueDate: hasDueDate ? dueDate : nil,
            completed: tracker.template.usesDuration ? true : false,
            trackerID: tracker.id
        )
        model.add(entry, syncToCalendar: false)
        dismiss()
    }
}

private extension TrackerFamily {
    var color: Color {
        switch self {
        case .money: .orange
        case .booksMedia: .indigo
        case .habits: .green
        case .things: .blue
        case .health: .teal
        case .mindset: .purple
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
