import SwiftUI

struct TodaySystemView: View {
    @Environment(AppModel.self) private var model
    @Environment(SystemFeatureModel.self) private var systemFeature
    let date: Date
    @State private var reviewKind: ReviewSheetKind?
    @State private var expandedProcessID: UUID?
    @State private var isEditingDashboard = false
    @State private var editingAction: SystemAction?

    private var snapshot: TodaySystemSnapshot {
        systemFeature.snapshot(on: date, timeline: model.entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            dashboardToolbar
            ForEach(Array(dashboardRows.enumerated()), id: \.offset) { _, row in
                if row.count == 1, let configuration = row.first {
                    dashboardWidget(configuration)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(row) { configuration in
                                dashboardWidget(configuration)
                                    .frame(minWidth: 300, maxWidth: .infinity)
                            }
                        }
                        VStack(spacing: 14) {
                            ForEach(row) { configuration in
                                dashboardWidget(configuration)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $reviewKind) { kind in
            SystemReviewSheet(date: date, kind: kind.kind) { review in
                systemFeature.saveReview(review)
            }
        }
        .sheet(item: $editingAction) { action in
            TaskPlanEditorSheet(
                action: action,
                isNew: !systemFeature.workspace.actions.contains(where: { $0.id == action.id }),
                canSchedule: canSchedule,
                onSave: {
                    systemFeature.upsertAction($0)
                    editingAction = nil
                },
                onDelete: {
                    systemFeature.deleteAction($0.id)
                    editingAction = nil
                },
                onPostpone: {
                    systemFeature.updateAction($0)
                    postpone($0)
                    editingAction = nil
                }
            )
        }
    }

    private var visibleLayout: [DashboardWidgetConfiguration] {
        systemFeature.dashboardLayout.filter(\.isVisible)
    }

    private var dashboardRows: [[DashboardWidgetConfiguration]] {
        var rows: [[DashboardWidgetConfiguration]] = []
        var pending: [DashboardWidgetConfiguration] = []
        for configuration in visibleLayout {
            if configuration.size == .expanded {
                if !pending.isEmpty { rows.append(pending); pending = [] }
                rows.append([configuration])
            } else {
                pending.append(configuration)
                if pending.count == 2 { rows.append(pending); pending = [] }
            }
        }
        if !pending.isEmpty { rows.append(pending) }
        return rows
    }

    private var dashboardToolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("For today")
                    .font(.title2.bold())
                Text(isEditingDashboard ? "Drag blocks to reorder them" : "Keep the day honest and leave room to live it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isEditingDashboard {
                if snapshot.actions.count < 3 {
                    Button {
                        editingAction = newPriorityAction
                    } label: {
                        Label("Add priority", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("3 priorities", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if isEditingDashboard, !systemFeature.hiddenDashboardWidgets.isEmpty {
                Menu {
                    ForEach(systemFeature.hiddenDashboardWidgets) { configuration in
                        Button {
                            systemFeature.setDashboardWidget(configuration.kind, visible: true)
                        } label: {
                            Label(configuration.kind.title, systemImage: configuration.kind.systemImage)
                        }
                    }
                } label: {
                    Label("Add block", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }
            if isEditingDashboard {
                Button("Reset") { systemFeature.resetDashboardLayout() }
                    .buttonStyle(.borderless)
            }
            Button(isEditingDashboard ? "Done" : "Customize") {
                withAnimation(.snappy) { isEditingDashboard.toggle() }
            }
            .buttonStyle(.bordered)
            .tint(isEditingDashboard ? .accentColor : nil)
        }
    }

    @ViewBuilder
    private func dashboardWidget(_ configuration: DashboardWidgetConfiguration) -> some View {
        let block = widgetChrome(configuration)
        if isEditingDashboard {
            block
                .draggable(configuration.kind.rawValue)
                .dropDestination(for: String.self) { values, _ in
                    guard let rawValue = values.first,
                          let source = TodayWidgetKind(rawValue: rawValue) else { return false }
                    withAnimation(.snappy) {
                        systemFeature.moveDashboardWidget(source, before: configuration.kind)
                    }
                    return true
                }
        } else {
            block.contextMenu {
                Menu("Size", systemImage: "rectangle.3.group") {
                    ForEach(DashboardWidgetSize.allCases) { size in
                        Button {
                            withAnimation(.snappy) {
                                systemFeature.setDashboardWidgetSize(configuration.kind, size: size)
                            }
                        } label: {
                            Label(size.displayName, systemImage: sizeIcon(size))
                        }
                    }
                }
                Button {
                    systemFeature.setDashboardWidget(configuration.kind, visible: false)
                } label: {
                    Label("Hide block", systemImage: "eye.slash")
                }
            }
        }
    }

    private func widgetChrome(_ configuration: DashboardWidgetConfiguration) -> some View {
        widgetContent(configuration)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                if isEditingDashboard {
                    HStack(spacing: 5) {
                        Menu {
                            ForEach(DashboardWidgetSize.allCases) { size in
                                Button {
                                    withAnimation(.snappy) {
                                        systemFeature.setDashboardWidgetSize(configuration.kind, size: size)
                                    }
                                } label: {
                                    Label(size.displayName, systemImage: sizeIcon(size))
                                }
                            }
                        } label: {
                            Label(configuration.size.displayName, systemImage: sizeIcon(configuration.size))
                                .font(.caption.weight(.semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .help("Choose widget size")
                        Button {
                            systemFeature.setDashboardWidget(configuration.kind, visible: false)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .help("Hide \(configuration.kind.title)")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                }
            }
            .overlay {
                if isEditingDashboard {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func widgetContent(_ configuration: DashboardWidgetConfiguration) -> some View {
        switch configuration.kind {
        case .overview:
            systemHeader(size: configuration.size)
        case .now:
            if let current = snapshot.currentAction {
                nowCard(current, size: configuration.size)
            } else {
                completedCard
            }
        case .nextActions:
            nextActionsCard(size: configuration.size)
        case .schedule:
            scheduleCard(size: configuration.size)
        case .review:
            reviewsCard(size: configuration.size)
        case .progress:
            systemProgress(size: configuration.size)
        }
    }

    private func sizeIcon(_ size: DashboardWidgetSize) -> String {
        switch size {
        case .compact: "rectangle"
        case .standard: "rectangle.split.2x1"
        case .expanded: "rectangle.inset.filled"
        }
    }

    private func systemHeader(size: DashboardWidgetSize) -> some View {
        Group {
            switch size {
            case .compact:
                HStack(spacing: 14) {
                    progressRing(diameter: 52, lineWidth: 6, compact: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your day")
                            .font(.headline)
                        Text(compactSystemSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            case .standard:
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        widgetEyebrow("A REALISTIC DAY", icon: "circle.dotted.circle")
                        Text("What matters today")
                            .font(.title2.bold())
                        Text(systemSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    progressRing(diameter: 72, lineWidth: 8, compact: false)
                }
            case .expanded:
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            widgetEyebrow("A REALISTIC DAY", icon: "circle.dotted.circle")
                            Text("What matters today")
                                .font(.title.bold())
                            Text(systemSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        progressRing(diameter: 82, lineWidth: 8, compact: false)
                    }
                    Divider()
                    HStack(spacing: 18) {
                        ForEach(snapshot.systemProgress.prefix(3)) { progress in
                            VStack(alignment: .leading, spacing: 5) {
                                Label(progress.system.title, systemImage: progress.system.icon)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                ProgressView(value: progress.fraction)
                                    .tint(color(for: progress.system))
                                Text("\(progress.evidenceCount) of \(progress.target) this week")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(size == .compact ? 14 : 18)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.13), Color.purple.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func progressRing(diameter: CGFloat, lineWidth: CGFloat, compact: Bool) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: completionFraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if compact {
                Text("\(snapshot.completedCount)/\(snapshot.actions.count)")
                    .font(.caption2.bold())
            } else {
                VStack(spacing: 0) {
                    Text("\(snapshot.completedCount)")
                        .font(.title3.bold())
                    Text("of \(snapshot.actions.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("\(snapshot.completedCount) of \(snapshot.actions.count) actions completed")
    }

    private func widgetEyebrow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }

    private func nowCard(_ action: SystemAction, size: DashboardWidgetSize) -> some View {
        let system = systemFeature.workspace.systems.first { $0.id == action.systemID }
        let process = systemFeature.workspace.processes.first { $0.id == action.processID }
        return Group {
            switch size {
            case .compact:
                HStack(spacing: 12) {
                    Image(systemName: system?.icon ?? "scope")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NOW · \(action.scheduledDate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button { complete(action) } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Complete \(action.title)")
                }
            case .standard:
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        widgetEyebrow("NOW", icon: "circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text(action.scheduledDate, format: .dateTime.hour().minute())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    actionIdentity(action, system: system)
                    if let process {
                        Label(process.trigger, systemImage: "arrow.triangle.branch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            case .expanded:
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        widgetEyebrow("CURRENT FOCUS", icon: "scope")
                        Spacer()
                        Text(action.scheduledDate, format: .dateTime.hour().minute())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    actionIdentity(action, system: system)
                    if let process {
                        Divider()
                        Label(process.trigger, systemImage: "bolt.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(process.title)
                            .font(.headline)
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(process.steps.sorted { $0.order < $1.order }) { step in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("\(step.order + 1)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 23, height: 23)
                                        .background(Color.accentColor, in: Circle())
                                    Text(step.title)
                                        .font(.caption.weight(.medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .padding(size == .compact ? 14 : 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.green.opacity(0.22))
        }
    }

    private func actionIdentity(_ action: SystemAction, system: PersonalSystem?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: system?.icon ?? "scope")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.title3.bold())
                Text("\(planningSummary(action)) · \(action.energy.rawValue) · \(system?.title ?? "Independent action")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actionMenu(action)
            Button("Complete") { complete(action) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var completedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("This is enough for today")
                    .font(.title3.bold())
                Text("Take a breath, then keep one honest thought for tomorrow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func nextActionsCard(size: DashboardWidgetSize) -> some View {
        let allNext = snapshot.actions.filter { !$0.isCompleted(on: date) }.dropFirst()
        let limit = size == .compact ? 1 : 2
        let displayed = Array(allNext.prefix(limit))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Worth making time for", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(allNext.count) waiting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if displayed.isEmpty {
                Text("Nothing else needs your attention.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayed) { action in
                    HStack(spacing: 10) {
                        Button { complete(action) } label: {
                            Image(systemName: action.isCompleted(on: date) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(action.isCompleted(on: date) ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Complete \(action.title)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                            Text(planningSummary(action))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if size == .expanded,
                               let system = systemFeature.workspace.systems.first(where: { $0.id == action.systemID }) {
                                Label("\(system.title) · \(action.energy.rawValue)", systemImage: system.icon)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        actionMenu(action)
                    }
                }
            }
            Divider()
            Label("Something new means something else waits.", systemImage: "leaf")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func scheduleCard(size: DashboardWidgetSize) -> some View {
        let agenda = model.calendarAgenda(on: date)
        let limit = size == .compact ? 1 : (size == .standard ? 3 : 8)
        let displayed = Array(agenda.prefix(limit))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Schedule", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if displayed.isEmpty {
                Text("No calendar commitments for this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayed, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.startDate, format: .dateTime.hour().minute())
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.blue)
                            .frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if size == .expanded {
                                Text("Until \(item.endDate.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func reviewsCard(size: DashboardWidgetSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("A moment for you", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                Spacer()
                if size == .expanded {
                    Text("Notice what the day taught you")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if size == .compact {
                let kind = relevantReviewKind
                reviewButton(
                    title: kind == .morning ? "Morning brief" : "Evening reflection",
                    icon: kind == .morning ? "sunrise.fill" : "moon.stars.fill",
                    completed: kind == .morning ? snapshot.morningReview != nil : snapshot.eveningReview != nil,
                    kind: kind
                )
            } else {
                reviewButton(
                    title: "Morning brief",
                    icon: "sunrise.fill",
                    completed: snapshot.morningReview != nil,
                    kind: .morning
                )
                reviewButton(
                    title: "Evening reflection",
                    icon: "moon.stars.fill",
                    completed: snapshot.eveningReview != nil,
                    kind: .evening
                )
                if size == .expanded {
                    Divider()
                    if let review = snapshot.eveningReview, !review.adjustment.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tomorrow’s adjustment")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(review.adjustment)
                                .font(.subheadline)
                        }
                    } else if let review = snapshot.morningReview, !review.intention.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today’s intention")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(review.intention)
                                .font(.subheadline)
                        }
                    } else {
                        Label("A short reflection can make tomorrow a little clearer.", systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(size == .compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var relevantReviewKind: ReviewSheetKind {
        if snapshot.morningReview == nil && Calendar.current.component(.hour, from: .now) < 16 { return .morning }
        return .evening
    }

    private func reviewButton(title: String, icon: String, completed: Bool, kind: ReviewSheetKind) -> some View {
        Button { reviewKind = kind } label: {
            HStack(spacing: 10) {
                Image(systemName: completed ? "checkmark.circle.fill" : icon)
                    .foregroundStyle(completed ? .green : .orange)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(completed ? "Completed" : "Takes about one minute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func systemProgress(size: DashboardWidgetSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Patterns this week")
                    .font(.title3.bold())
                Spacer()
                Text("This week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            switch size {
            case .compact:
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Overall consistency")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(averageProgress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.bold())
                        }
                        ProgressView(value: averageProgress)
                            .tint(.blue)
                    }
                }
            case .standard:
                VStack(spacing: 10) {
                    ForEach(snapshot.systemProgress.prefix(3)) { progress in
                        HStack(spacing: 10) {
                            Image(systemName: progress.system.icon)
                                .foregroundStyle(color(for: progress.system))
                                .frame(width: 24)
                            Text(progress.system.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            ProgressView(value: progress.fraction)
                                .tint(color(for: progress.system))
                                .frame(maxWidth: 110)
                            Text("\(progress.evidenceCount)/\(progress.target)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .expanded:
                HStack(spacing: 12) {
                    ForEach(snapshot.systemProgress) { progress in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: progress.system.icon)
                                    .foregroundStyle(color(for: progress.system))
                                Spacer()
                                Text("\(progress.evidenceCount)/\(progress.target)")
                                    .font(.caption.bold())
                            }
                            Text(progress.system.title)
                                .font(.headline)
                            Text(progress.system.purpose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ProgressView(value: progress.fraction)
                                .tint(color(for: progress.system))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
        .padding(size == .compact ? 14 : 0)
        .background(size == .compact ? Color.secondary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var averageProgress: Double {
        guard !snapshot.systemProgress.isEmpty else { return 0 }
        return snapshot.systemProgress.map(\.fraction).reduce(0, +) / Double(snapshot.systemProgress.count)
    }

    private var completionFraction: Double {
        snapshot.actions.isEmpty ? 1 : Double(snapshot.completedCount) / Double(snapshot.actions.count)
    }

    private var systemSummary: String {
        let remaining = snapshot.actions.count - snapshot.completedCount
        if remaining == 0 { return "You have done enough. Reflect, recover, and let tomorrow wait." }
        return "\(min(remaining, 3)) meaningful \(remaining == 1 ? "commitment" : "commitments") for today. The rest can wait."
    }

    private var compactSystemSummary: String {
        let remaining = snapshot.actions.count - snapshot.completedCount
        if remaining == 0 { return "Complete · ready to reflect" }
        return "\(remaining) \(remaining == 1 ? "action" : "actions") remaining"
    }

    private func color(for system: PersonalSystem) -> Color {
        switch system.colorName {
        case "green": .green
        case "purple": .purple
        case "orange": .orange
        default: .blue
        }
    }

    private func planningSummary(_ action: SystemAction) -> String {
        switch action.effectivePlanningMode {
        case .anytime:
            return "Anytime · \(action.durationMinutes) min"
        case .exact:
            let end = action.scheduledDate.addingTimeInterval(TimeInterval(action.durationMinutes * 60))
            return "\(action.scheduledDate.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
        case .window:
            let end = action.windowEndDate ?? action.scheduledDate.addingTimeInterval(TimeInterval(action.durationMinutes * 60))
            return "\(action.scheduledDate.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened)) · \(action.durationMinutes) min"
        }
    }

    private func actionMenu(_ action: SystemAction) -> some View {
        Menu {
            Button("Edit", systemImage: "pencil") { editingAction = action }
            Button("Move to tomorrow", systemImage: "calendar.badge.clock") { postpone(action) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                systemFeature.deleteAction(action.id)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("More options for \(action.title)")
    }

    private func postpone(_ action: SystemAction) {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: action.scheduledDate) ?? action.scheduledDate
        systemFeature.postponeAction(action.id, to: tomorrow)
    }

    private var newPriorityAction: SystemAction {
        let start = Calendar.current.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
        return SystemAction(
            title: "",
            scheduledDate: start,
            cadence: nil,
            durationMinutes: 30,
            energy: .medium,
            priority: max(1, 3 - snapshot.actions.count),
            planningMode: .anytime
        )
    }

    private func canSchedule(_ action: SystemAction) -> Bool {
        let occupied = systemFeature.workspace.actions.filter {
            $0.id != action.id && $0.occurs(on: action.scheduledDate)
        }
        return occupied.count < 3
    }

    private func complete(_ action: SystemAction) {
        guard !action.isCompleted(on: date) else { return }
        systemFeature.toggle(action, on: date)
        guard let system = systemFeature.workspace.systems.first(where: { $0.id == action.systemID }) else { return }
        let timestamp: Date
        if Calendar.current.isDateInToday(date) {
            timestamp = .now
        } else {
            timestamp = Calendar.current.date(
                bySettingHour: Calendar.current.component(.hour, from: action.scheduledDate),
                minute: Calendar.current.component(.minute, from: action.scheduledDate),
                second: 0,
                of: date
            ) ?? date
        }
        model.add(
            LogEntry(
                timestamp: timestamp,
                category: system.evidenceCategory,
                title: action.title,
                note: "Completed with Asitra · \(system.title)",
                durationMinutes: action.durationMinutes,
                status: .completed,
                lifeArea: system.evidenceCategory.defaultLifeArea,
                deviceSource: currentDeviceSource,
                externalIdentifier: "system-action-\(action.id.uuidString)-\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)"
            ),
            syncToCalendar: false
        )
    }

    private var currentDeviceSource: DeviceSource {
#if os(macOS)
        .mac
#else
        .phone
#endif
    }
}

private struct TaskPlanEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SystemAction
    @State private var confirmsDelete = false

    let isNew: Bool
    let canSchedule: (SystemAction) -> Bool
    let onSave: (SystemAction) -> Void
    let onDelete: (SystemAction) -> Void
    let onPostpone: (SystemAction) -> Void

    init(
        action: SystemAction,
        isNew: Bool,
        canSchedule: @escaping (SystemAction) -> Bool,
        onSave: @escaping (SystemAction) -> Void,
        onDelete: @escaping (SystemAction) -> Void,
        onPostpone: @escaping (SystemAction) -> Void
    ) {
        _draft = State(initialValue: action)
        self.isNew = isNew
        self.canSchedule = canSchedule
        self.onSave = onSave
        self.onDelete = onDelete
        self.onPostpone = onPostpone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What matters") {
                    TextField("Task", text: $draft.title)
                    DatePicker(
                        "Day",
                        selection: $draft.scheduledDate,
                        displayedComponents: .date
                    )
                }

                Section {
                    Picker("Time plan", selection: planningMode) {
                        ForEach(TaskPlanningMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if draft.effectivePlanningMode != .anytime {
                        DatePicker(
                            draft.effectivePlanningMode == .window ? "Available from" : "Starts",
                            selection: $draft.scheduledDate,
                            displayedComponents: .hourAndMinute
                        )
                    }

                    if draft.effectivePlanningMode == .window {
                        DatePicker(
                            "Available until",
                            selection: windowEndDate,
                            in: draft.scheduledDate...,
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Stepper(value: $draft.durationMinutes, in: 5...720, step: 5) {
                        LabeledContent("Time needed", value: durationLabel)
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("When should it happen?")
                } footer: {
                    Text(scheduleHelp)
                }

                Section("Quick choices") {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            quickChoice("Morning", hour: 9)
                            quickChoice("Afternoon", hour: 14)
                            quickChoice("Evening", hour: 18)
                            Button("Anytime") {
                                draft.planningMode = .anytime
                                draft.windowEndDate = nil
                            }
                        }
                        VStack(alignment: .leading) {
                            quickChoice("Morning", hour: 9)
                            quickChoice("Afternoon", hour: 14)
                            quickChoice("Evening", hour: 18)
                            Button("Anytime") {
                                draft.planningMode = .anytime
                                draft.windowEndDate = nil
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if !isNew {
                    Section {
                        Button("Move to tomorrow", systemImage: "calendar.badge.clock") {
                            onPostpone(draft)
                            dismiss()
                        }
                        Button("Delete task", systemImage: "trash", role: .destructive) {
                            confirmsDelete = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Plan task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this task?",
                isPresented: $confirmsDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete(draft)
                    dismiss()
                }
            } message: {
                Text("This removes the task from your plan. Completed timeline entries remain intact.")
            }
        }
        .frame(minWidth: 390, minHeight: 540)
    }

    private var planningMode: Binding<TaskPlanningMode> {
        Binding(
            get: { draft.effectivePlanningMode },
            set: { mode in
                draft.planningMode = mode
                if mode == .window {
                    draft.windowEndDate = draft.scheduledDate.addingTimeInterval(3 * 60 * 60)
                } else {
                    draft.windowEndDate = nil
                }
            }
        )
    }

    private var windowEndDate: Binding<Date> {
        Binding(
            get: {
                draft.windowEndDate
                    ?? draft.scheduledDate.addingTimeInterval(TimeInterval(max(draft.durationMinutes, 60) * 60))
            },
            set: { draft.windowEndDate = $0 }
        )
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validationMessage == nil
    }

    private var validationMessage: String? {
        guard canSchedule(draft) else {
            return "That day already has three priorities. Move or postpone one first."
        }
        guard draft.effectivePlanningMode == .window, let end = draft.windowEndDate else { return nil }
        let availableMinutes = Int(end.timeIntervalSince(draft.scheduledDate) / 60)
        if availableMinutes <= 0 { return "The end of the window must be after its start." }
        if draft.durationMinutes > availableMinutes {
            return "The task needs more time than this window provides."
        }
        return nil
    }

    private var durationLabel: String {
        if draft.durationMinutes < 60 { return "\(draft.durationMinutes) min" }
        let hours = draft.durationMinutes / 60
        let minutes = draft.durationMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }

    private var scheduleHelp: String {
        switch draft.effectivePlanningMode {
        case .anytime:
            "Keep it on this day without forcing a time."
        case .exact:
            "Reserve a clear start time; the end follows from the time needed."
        case .window:
            "Choose a flexible span in which Asitra can help you fit the task."
        }
    }

    private func quickChoice(_ title: String, hour: Int) -> some View {
        Button(title) {
            draft.planningMode = .exact
            draft.windowEndDate = nil
            draft.scheduledDate = Calendar.current.date(
                bySettingHour: hour,
                minute: 0,
                second: 0,
                of: draft.scheduledDate
            ) ?? draft.scheduledDate
        }
    }
}

private enum ReviewSheetKind: String, Identifiable {
    case morning
    case evening

    var id: Self { self }
    var kind: SystemReviewKind { self == .morning ? .morning : .evening }
}

private struct SystemReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let kind: SystemReviewKind
    let onSave: (SystemReview) -> Void
    @State private var energy = 3
    @State private var intention = ""
    @State private var worked = ""
    @State private var friction = ""
    @State private var adjustment = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Energy", selection: $energy) {
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Energy")
                } footer: {
                    Text("1 is depleted; 5 is fully energized.")
                }

                if kind == .morning {
                    Section("Today’s intention") {
                        TextField("What matters most today?", text: $intention, axis: .vertical)
                            .lineLimit(3...6)
                        TextField("What could create friction?", text: $friction, axis: .vertical)
                            .lineLimit(2...5)
                    }
                } else {
                    Section("Reflection") {
                        TextField("What worked today?", text: $worked, axis: .vertical)
                            .lineLimit(2...5)
                        TextField("What made the day harder than it needed to be?", text: $friction, axis: .vertical)
                            .lineLimit(2...5)
                        TextField("What should change tomorrow?", text: $adjustment, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(kind == .morning ? "Morning Brief" : "Evening Reflection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(SystemReview(
                            date: date,
                            kind: kind,
                            energy: energy,
                            intention: intention,
                            worked: worked,
                            friction: friction,
                            adjustment: adjustment
                        ))
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 390, minHeight: 430)
    }
}
