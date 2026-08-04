import SwiftUI

private enum TaskPlanningView: String, CaseIterable, Identifiable {
    case matrix = "Priority matrix"
    case board = "Board"

    var id: Self { self }
    var systemImage: String { self == .matrix ? "square.grid.2x2" : "rectangle.3.group" }
}

private enum TaskQuadrant: String, CaseIterable, Identifiable {
    case doNow = "Do now"
    case plan = "Plan"
    case simplify = "Simplify"
    case later = "Later"

    var id: Self { self }

    var subtitle: String {
        switch self {
        case .doNow: "Important and urgent"
        case .plan: "Important, not urgent"
        case .simplify: "Urgent, not important"
        case .later: "Not urgent or important"
        }
    }

    var tint: Color {
        switch self {
        case .doNow: .green
        case .plan: .blue
        case .simplify: .orange
        case .later: .secondary
        }
    }

    func contains(_ entry: LogEntry) -> Bool {
        switch self {
        case .doNow: entry.taskImportant == true && entry.taskUrgent == true
        case .plan: entry.taskImportant == true && entry.taskUrgent != true
        case .simplify: entry.taskImportant != true && entry.taskUrgent == true
        case .later: entry.taskImportant != true && entry.taskUrgent != true
        }
    }
}

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var planningView: TaskPlanningView = .matrix
    @State private var taskText = ""
    @State private var newTaskImportant = false
    @State private var newTaskUrgent = false
    @State private var columnToEdit: TaskBoardColumn?
    @State private var columnName = ""
    @State private var showingColumnEditor = false

    private var tasks: [LogEntry] {
        model.entries.filter { $0.category == .list }
    }

    private var openTasks: [LogEntry] { tasks.filter { !$0.isCompleted } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                taskInbox
                viewToolbar
                if planningView == .matrix {
                    matrix
                } else {
                    board
                }
            }
            .padding()
        }
        .navigationTitle("Tasks")
        .sheet(isPresented: $showingColumnEditor) {
            columnEditor
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CLEAR THE MIND")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.green)
            Text("Tasks")
                .font(.largeTitle.weight(.semibold))
            Text("Put everything down first. Then decide what deserves attention and where it belongs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var taskInbox: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Task inbox", systemImage: "tray")
                .font(.headline)
            Text("Capture it now. Organize it in a second.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("What is on your mind?", text: $taskText)
                    .textFieldStyle(.plain)
                    .onSubmit(addTask)

                Button(action: addTask) {
                    Label("Add task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                PriorityToggle(title: "Important", systemImage: "flag", isOn: $newTaskImportant, tint: .green)
                PriorityToggle(title: "Urgent", systemImage: "bolt", isOn: $newTaskUrgent, tint: .orange)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.secondary.opacity(0.15)) }
    }

    private var viewToolbar: some View {
        HStack {
            Picker("Task view", selection: $planningView) {
                ForEach(TaskPlanningView.allCases) { view in
                    Label(view.rawValue, systemImage: view.systemImage).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 430)

            Spacer()
            Text("\(openTasks.count) open · \(tasks.count - openTasks.count) done")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var matrix: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 12)], spacing: 12) {
            ForEach(TaskQuadrant.allCases) { quadrant in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(quadrant.rawValue)
                                .font(.title3.weight(.semibold))
                            Text(quadrant.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(openTasks.filter(quadrant.contains).count)")
                            .font(.caption.weight(.bold))
                            .padding(7)
                            .background(.background, in: Circle())
                    }

                    ForEach(openTasks.filter(quadrant.contains)) { entry in
                        TaskPlanningRow(entry: entry, compact: true)
                    }

                    if !openTasks.contains(where: quadrant.contains) {
                        Text("Nothing here. That is useful information too.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 72)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
                .background(quadrant.tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(quadrant.tint.opacity(0.2)) }
            }
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Drag tasks between columns, or choose a column from each task menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    columnToEdit = nil
                    columnName = ""
                    showingColumnEditor = true
                } label: {
                    Label("Add column", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.systemFeature.taskColumns) { column in
                        TaskBoardColumnView(
                            column: column,
                            entries: tasks.filter { columnID(for: $0) == column.id },
                            edit: {
                                columnToEdit = column
                                columnName = column.name
                                showingColumnEditor = true
                            },
                            moveEntry: { entry in move(entry, to: column.id) }
                        )
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var columnEditor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Column name", text: $columnName)
                } footer: {
                    Text("A column is another stage between capturing a task and finishing it.")
                }
            }
            .navigationTitle(columnToEdit == nil ? "Add column" : "Rename column")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingColumnEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let columnToEdit {
                            model.systemFeature.renameTaskColumn(id: columnToEdit.id, name: columnName)
                        } else {
                            model.systemFeature.addTaskColumn(name: columnName)
                        }
                        showingColumnEditor = false
                    }
                    .disabled(columnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }

    private func addTask() {
        let title = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let taskList = model.defaultList(for: .task)
        model.add(LogEntry(
            timestamp: .now,
            category: .list,
            title: title,
            lifeArea: .personal,
            deviceSource: .offline,
            listKind: .task,
            listID: taskList?.id,
            completed: false,
            taskImportant: newTaskImportant,
            taskUrgent: newTaskUrgent,
            taskColumnID: TaskBoardColumn.toDoID
        ))
        taskText = ""
        newTaskImportant = false
        newTaskUrgent = false
    }

    private func columnID(for entry: LogEntry) -> UUID {
        if entry.isCompleted { return TaskBoardColumn.doneID }
        let available = model.systemFeature.taskColumns.map(\.id)
        if let id = entry.taskColumnID, available.contains(id) { return id }
        return available.first ?? TaskBoardColumn.toDoID
    }

    private func move(_ entry: LogEntry, to columnID: UUID) {
        var updated = entry
        updated.taskColumnID = columnID
        updated.isCompleted = columnID == TaskBoardColumn.doneID
        model.update(updated)
    }
}

private struct PriorityToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .foregroundStyle(isOn ? tint : .secondary)
                .background(isOn ? tint.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(isOn ? tint.opacity(0.35) : Color.secondary.opacity(0.16)) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct TaskPlanningRow: View {
    @Environment(AppModel.self) private var model
    let entry: LogEntry
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 9) {
                Button { model.toggleCompleted(entry) } label: {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(entry.isCompleted)
                    if let list = model.list(withID: entry.listID) {
                        Text(list.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    ForEach(model.systemFeature.taskColumns) { column in
                        Button(column.name) { move(to: column.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 6) {
                Button { toggleImportant() } label: {
                    Label("Important", systemImage: "flag")
                }
                .tint(entry.taskImportant == true ? .green : .secondary)

                Button { toggleUrgent() } label: {
                    Label("Urgent", systemImage: "bolt")
                }
                .tint(entry.taskUrgent == true ? .orange : .secondary)
            }
            .font(.caption2.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.secondary.opacity(0.14)) }
        .draggable(entry.id.uuidString)
    }

    private func toggleImportant() {
        var updated = entry
        updated.taskImportant = entry.taskImportant != true
        model.update(updated)
    }

    private func toggleUrgent() {
        var updated = entry
        updated.taskUrgent = entry.taskUrgent != true
        model.update(updated)
    }

    private func move(to columnID: UUID) {
        var updated = entry
        updated.taskColumnID = columnID
        updated.isCompleted = columnID == TaskBoardColumn.doneID
        model.update(updated)
    }
}

private struct TaskBoardColumnView: View {
    @Environment(AppModel.self) private var model
    let column: TaskBoardColumn
    let entries: [LogEntry]
    let edit: () -> Void
    let moveEntry: (LogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(column.name)
                    .font(.headline)
                Text("\(entries.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: edit) { Image(systemName: "pencil") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename \(column.name)")
            }

            ForEach(entries) { entry in
                TaskPlanningRow(entry: entry)
            }

            if entries.isEmpty {
                Text("Drop tasks here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.18), style: StrokeStyle(dash: [5])) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 300)
        .frame(minHeight: 440, alignment: .top)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.secondary.opacity(0.13)) }
        .dropDestination(for: String.self) { ids, _ in
            guard let rawID = ids.first,
                  let id = UUID(uuidString: rawID),
                  let entry = model.entries.first(where: { $0.id == id }) else { return false }
            moveEntry(entry)
            return true
        }
    }
}

#Preview {
    NavigationStack { TasksView() }
        .environment(AppModel(container: PersistenceController.makeContainer(inMemory: true)))
}
