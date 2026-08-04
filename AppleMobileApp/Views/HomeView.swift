import AVFoundation
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
    @State private var voiceCapture = VoiceCaptureService()
    @State private var voicePrefix = ""
    @State private var quickPhotoSelection: PhotosPickerItem?
    @State private var quickPhotoData: Data?
    @State private var imageAnalysis: ImageCaptureAnalysis?
    @State private var isAnalyzingImage = false
    @State private var captureError: String?
    @State private var pendingCalendarCapture: PendingCalendarCapture?
    @State private var editingEntry: LogEntry?
    @State private var visiblePastEntryCount = 40
    @State private var visibleFutureEntryCount = 30
    @FocusState private var quickCaptureFocused: Bool

    private var entries: [LogEntry] { model.entries(on: selectedDate) }
    private var quickSuggestion: SmartCapture { SmartCapture(text: quickInput) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(alignment: .leading, spacing: 22) {
                        greetingHeader
                        dateHeader
                        quickCapture
                        TodaySystemView(date: selectedDate)
                        summary
                        timeline
                    }
                    .padding()
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                } header: {
                    dayBoundaryHeader
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
        }
        .navigationTitle(dayRelationship(for: selectedDate))
        .sheet(isPresented: $showingAddEntry) {
            AddEntryView(defaultDate: selectedDate, initialText: detailsDraft) {
                quickInput = ""
            }
                .environment(model)
        }
        .sheet(item: $pendingCalendarCapture) { capture in
            CalendarEntryPreview(
                capture: capture,
                onCancel: { pendingCalendarCapture = nil },
                onSave: saveConfirmedCalendarCapture
            )
        }
        .sheet(item: $editingEntry) { entry in
            EditTimelineEntryView(entry: entry) { updated in
                model.update(updated)
                editingEntry = nil
            }
        }
        .onChange(of: voiceCapture.transcript) { _, transcript in
            guard voiceCapture.isRecording || voiceCapture.recordingURL != nil else { return }
            quickInput = [voicePrefix, transcript]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: voicePrefix.isEmpty ? "" : " ")
        }
        .onChange(of: voiceCapture.errorMessage) { _, error in
            if let error { captureError = error }
        }
        .onChange(of: quickPhotoSelection) { _, item in
            guard let item else { return }
            analyzeQuickPhoto(item)
        }
        .onChange(of: selectedDate) { _, _ in
            // Each date is its own bounded timeline. Reset progressive loading
            // rather than carrying scroll/loading state into another day.
            visiblePastEntryCount = 40
            visibleFutureEntryCount = 30
        }
        .alert("Capture needs attention", isPresented: Binding(
            get: { captureError != nil },
            set: { if !$0 { captureError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(captureError ?? "Please try again.")
        }
#if os(macOS)
        .onAppear { quickCaptureFocused = true }
#endif
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add anything", systemImage: "sparkles")
                .font(.headline)

            Text("Type or talk naturally. Asitra organizes it before anything is saved.")
                .font(.caption)
                .foregroundStyle(.secondary)

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

            if let quickPhotoData {
                HStack(alignment: .top, spacing: 12) {
                    AttachmentImage(data: quickPhotoData)
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            isAnalyzingImage ? "Interpreting photo…" : "Photo interpreted on device",
                            systemImage: isAnalyzingImage ? "sparkles" : "checkmark.shield"
                        )
                        .font(.caption.weight(.semibold))
                        if let imageAnalysis, !imageAnalysis.labels.isEmpty {
                            Text(imageAnalysis.labels.prefix(3).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                    Button {
                        self.quickPhotoData = nil
                        quickPhotoSelection = nil
                        imageAnalysis = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove photo")
                }
            }

            if voiceCapture.recordingURL != nil {
                HStack(spacing: 10) {
                    Image(systemName: voiceCapture.isRecording ? "waveform.circle.fill" : "waveform.circle")
                        .foregroundStyle(voiceCapture.isRecording ? .red : .blue)
                    Text(voiceCapture.isRecording ? "Listening… speak naturally" : "Voice note ready")
                        .font(.caption.weight(.semibold))
                    if voiceCapture.usesOnDeviceRecognition {
                        Text("On-device")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    Button("Discard") {
                        voiceCapture.reset()
                        quickInput = voicePrefix
                    }
                    .buttonStyle(.borderless)
                }
            }

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

                if let minutes = quickSuggestion.durationMinutes {
                    Label(
                        minutes >= 60 && minutes.isMultiple(of: 60) ? "\(minutes / 60) hr" : "\(minutes) min",
                        systemImage: "clock"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                if let start = quickSuggestion.calendarStartDate,
                   let end = quickSuggestion.calendarEndDate {
                    Label(
                        "Calendar • \(start.formatted(date: .abbreviated, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))",
                        systemImage: "calendar.badge.plus"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                } else if quickSuggestion.category == .work, quickSuggestion.durationMinutes != nil {
                    Label("Timeline only", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }

                Spacer()

                PhotosPicker(selection: $quickPhotoSelection, matching: .images) {
                    Label("Photo", systemImage: "photo.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(isAnalyzingImage)
                .help("Add and interpret a photo")

                Button(action: toggleVoiceCapture) {
                    Label(
                        voiceCapture.isRecording ? "Stop" : "Talk",
                        systemImage: voiceCapture.isRecording ? "stop.circle.fill" : "mic.fill"
                    )
                    .foregroundStyle(voiceCapture.isRecording ? .red : .primary)
                }
                .buttonStyle(.bordered)
                .help(voiceCapture.isRecording ? "Stop voice note" : "Record a voice note")

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
        if voiceCapture.isRecording { voiceCapture.stop() }
        guard !quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let audioData = voiceCapture.recordingURL.flatMap { try? Data(contentsOf: $0) }
        let captureNote: String
        if let analysis = imageAnalysis, !analysis.recognizedText.isEmpty {
            captureNote = "Recognized from the attached photo on device:\n\(analysis.recognizedText)"
        } else {
            captureNote = ""
        }
        let scheduledDate = quickSuggestion.calendarStartDate
        if let startDate = quickSuggestion.calendarStartDate,
           let endDate = quickSuggestion.calendarEndDate {
            pendingCalendarCapture = PendingCalendarCapture(
                sourceText: quickInput.trimmingCharacters(in: .whitespacesAndNewlines),
                title: quickSuggestion.calendarTitle ?? "Meeting",
                location: quickSuggestion.calendarLocation ?? "",
                startDate: startDate,
                endDate: endDate,
                reminderLeadMinutes: quickSuggestion.reminderLeadMinutes,
                photoData: quickPhotoData,
                audioData: audioData,
                captureNote: captureNote
            )
            return
        }
        model.addCapturedText(
            quickInput,
            on: selectedDate,
            photoData: quickPhotoData,
            audioData: audioData,
            captureNote: captureNote
        )
        quickInput = ""
        voicePrefix = ""
        voiceCapture.reset()
        quickPhotoData = nil
        quickPhotoSelection = nil
        imageAnalysis = nil
        if let scheduledDate { selectedDate = scheduledDate }
        quickCaptureFocused = true
    }

    private func saveConfirmedCalendarCapture(_ capture: PendingCalendarCapture) {
        let cleanedLocation = capture.location.trimmingCharacters(in: .whitespacesAndNewlines)
        model.addCapturedText(
            capture.sourceText,
            on: selectedDate,
            photoData: capture.photoData,
            audioData: capture.audioData,
            captureNote: capture.captureNote,
            calendarOverride: CalendarCaptureOverride(
                title: capture.title.trimmingCharacters(in: .whitespacesAndNewlines),
                location: cleanedLocation.isEmpty ? nil : cleanedLocation,
                startDate: capture.startDate,
                endDate: capture.endDate,
                reminderLeadMinutes: capture.reminderLeadMinutes
            )
        )
        selectedDate = capture.startDate
        pendingCalendarCapture = nil
        quickInput = ""
        voicePrefix = ""
        voiceCapture.reset()
        quickPhotoData = nil
        quickPhotoSelection = nil
        imageAnalysis = nil
        quickCaptureFocused = true
    }

    private func toggleVoiceCapture() {
        if voiceCapture.isRecording {
            voiceCapture.stop()
        } else {
            voicePrefix = quickInput.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { await voiceCapture.start() }
        }
    }

    private func analyzeQuickPhoto(_ item: PhotosPickerItem) {
        isAnalyzingImage = true
        Task {
            defer { isAnalyzingImage = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                captureError = "Asitra could not load that photo."
                return
            }
            quickPhotoData = data
            do {
                let analysis = try await ImageIntelligenceService.analyze(data)
                imageAnalysis = analysis
                if quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    quickInput = analysis.suggestedCapture
                }
            } catch {
                captureError = error.localizedDescription
            }
        }
    }

    private var dateHeader: some View {
        ElegantCalendar(selectedDate: $selectedDate, isExpanded: $calendarExpanded)
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingTitle)
                .font(.largeTitle.bold())
            Text(Calendar.current.isDateInToday(selectedDate)
                ? "Choose a day you can actually live."
                : selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greetingTitle: String {
        guard Calendar.current.isDateInToday(selectedDate) else { return dayRelationship(for: selectedDate) }
        return switch Calendar.current.component(.hour, from: .now) {
        case 0..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var dayBoundaryHeader: some View {
        HStack(spacing: 12) {
            Button { moveSelectedDay(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")

            VStack(alignment: .leading, spacing: 1) {
                Text(dayRelationship(for: selectedDate))
                    .font(.headline)
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(entries.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())

            Button { moveSelectedDay(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next day")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func moveSelectedDay(by value: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) else { return }
        withAnimation(.snappy) { selectedDate = date }
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
        LazyVStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(dayRelationship(for: selectedDate))’s timeline")
                        .font(.title2.bold())
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }

            if Calendar.current.isDateInToday(selectedDate) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    continuousTodayTimeline(now: context.date)
                }
            } else if entries.isEmpty {
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
                timelineRows(entries)
            }
        }
    }

    @ViewBuilder
    private func continuousTodayTimeline(now: Date) -> some View {
        // Never pull adjacent days into Today's future/past sections.
        let ordered = entries.sorted { $0.timestamp < $1.timestamp }
        let future = ordered.filter { $0.timestamp > now }
        let past = ordered.lazy.reversed().filter { $0.timestamp <= now }
        let visibleFuture = Array(future.prefix(visibleFutureEntryCount))
        let visiblePast = Array(past.prefix(visiblePastEntryCount))

        NowTimelineMarker(now: now)

        if !future.isEmpty {
            timelineSectionHeader("Upcoming", count: future.count, icon: "arrow.down.forward")
            timelineRows(visibleFuture)
            if visibleFuture.count < future.count {
                progressiveTimelineLoader {
                    visibleFutureEntryCount = min(visibleFutureEntryCount + 30, future.count)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                Text("Nothing scheduled after now")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }

        if !past.isEmpty {
            timelineSectionHeader("Earlier", count: past.count, icon: "arrow.up.backward")
            timelineRows(visiblePast)
            if visiblePast.count < past.count {
                progressiveTimelineLoader {
                    visiblePastEntryCount = min(visiblePastEntryCount + 40, past.count)
                }
            }
        }
    }

    private func progressiveTimelineLoader(load: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading more entries…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onAppear(perform: load)
    }

    private func timelineSectionHeader(_ title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .font(.headline)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func timelineRows(_ values: [LogEntry]) -> some View {
        ForEach(values) { entry in
            TimelineRow(
                entry: entry,
                attachmentData: model.attachmentData(for: entry),
                audioURL: model.audioAttachmentURL(for: entry),
                isLast: entry.id == values.last?.id,
                onEdit: { editingEntry = entry },
                onDelete: { model.delete(entry) }
            )
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }

    private func dayRelationship(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

private struct PendingCalendarCapture: Identifiable {
    let id = UUID()
    var sourceText: String
    var title: String
    var location: String
    var startDate: Date
    var endDate: Date
    var reminderLeadMinutes: Int?
    var photoData: Data?
    var audioData: Data?
    var captureNote: String
}

private struct CalendarEntryPreview: View {
    @State private var draft: PendingCalendarCapture
    let onCancel: () -> Void
    let onSave: (PendingCalendarCapture) -> Void

    init(
        capture: PendingCalendarCapture,
        onCancel: @escaping () -> Void,
        onSave: @escaping (PendingCalendarCapture) -> Void
    ) {
        _draft = State(initialValue: capture)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Review before saving", systemImage: "checkmark.shield")
                        .font(.headline)
                    Text("Nothing will be added to Asitra or Apple Calendar until you confirm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Calendar entry") {
                    TextField("Title", text: $draft.title)
                    TextField("Location", text: $draft.location)
                    DatePicker("Starts", selection: $draft.startDate)
                    DatePicker(
                        "Ends",
                        selection: $draft.endDate,
                        in: draft.startDate.addingTimeInterval(60)...
                    )
                }

                if let lead = draft.reminderLeadMinutes {
                    Section("Alert") {
                        Label("\(lead) minutes before", systemImage: "bell")
                    }
                }

                Section("Original input") {
                    Text(draft.sourceText)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Confirm Calendar Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Calendar") { onSave(draft) }
                        .disabled(
                            draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.endDate <= draft.startDate
                        )
                }
            }
        }
        .frame(minWidth: 400, minHeight: 460)
    }
}

private struct NowTimelineMarker: View {
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Text(now.formatted(.dateTime.hour().minute()))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.red)
                .frame(width: 66, alignment: .leading)

            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .overlay { Circle().stroke(.red.opacity(0.22), lineWidth: 7) }

            Rectangle()
                .fill(.red.opacity(0.55))
                .frame(height: 1)

            VStack(alignment: .trailing, spacing: 1) {
                Text("Now")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now, \(now.formatted(date: .complete, time: .shortened))")
    }
}

private struct ElegantCalendar: View {
    @Environment(AppModel.self) private var model
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
                            Text(isExpanded ? displayedMonth.formatted(.dateTime.month(.wide).year()) : "Calendar")
                                .font(.title3.bold())
                            Text(isExpanded ? "Choose a date" : "Tap to open the month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Close calendar" : "Open calendar")

                Spacer()

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

                if entryCount(on: selectedDate) > 0 {
                    Text("\(entryCount(on: selectedDate)) \(entryCount(on: selectedDate) == 1 ? "entry" : "entries")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
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

    private var relativeDayStrip: some View {
        HStack(spacing: 8) {
            relativeDayButton(title: "Yesterday", offset: -1)
            relativeDayButton(title: "Today", offset: 0)
            relativeDayButton(title: "Tomorrow", offset: 1)
        }
    }

    private func relativeDayButton(title: String, offset: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        return Button { select(date) } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(selected ? selectedForeground.opacity(0.8) : .secondary)
                if entryCount(on: date) > 0 {
                    Text("\(entryCount(on: date))")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .frame(minHeight: 15)
                        .background(selected ? selectedForeground.opacity(0.16) : Color.blue.opacity(0.14), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? selectedForeground : .primary)
            .background(selected ? Color.primary : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { date in
                let selected = calendar.isDate(date, inSameDayAs: selectedDate)
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
                        calendarActivity(count: entryCount(on: date), selected: selected)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        return Button {
            select(date)
            withAnimation(.snappy) { isExpanded = false }
        } label: {
            ZStack(alignment: .bottomTrailing) {
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
                let count = entryCount(on: date)
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, count > 9 ? 4 : 0)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Color.blue, in: Capsule())
                        .offset(x: 2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
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
        displayedMonth = monthStart(for: next)
    }

    private func select(_ date: Date) {
        selectedDate = date
        displayedMonth = monthStart(for: selectedDate)
    }

    private func relativeName(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    @ViewBuilder
    private func calendarActivity(count: Int, selected: Bool) -> some View {
        if count > 0 {
            HStack(spacing: 2) {
                Circle()
                    .fill(selected ? selectedForeground.opacity(0.8) : Color.blue)
                    .frame(width: 4, height: 4)
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? selectedForeground.opacity(0.8) : .secondary)
                }
            }
            .frame(height: 8)
        } else {
            Color.clear.frame(height: 8)
        }
    }

    private func entryCount(on date: Date) -> Int {
        model.entries(on: date).count
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
    let audioURL: URL?
    let isLast: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 7) {
                VStack(spacing: 1) {
                    Text(entry.timestamp, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(entry.timestamp, format: .dateTime.day().month(.abbreviated))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: entry.category.systemImage)
                    .font(.headline)
                    .foregroundStyle(categoryColor)
                    .frame(width: 36, height: 36)
                    .background(categoryColor.opacity(0.14), in: Circle())

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 66)

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
                    Menu {
                        Button("Edit", systemImage: "pencil", action: onEdit)
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Entry actions")
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


                if let start = entry.calendarStartDate {
                    let end = entry.calendarEndDate ?? start.addingTimeInterval(3600)
                    HStack(spacing: 10) {
                        Label(
                            "\(start.formatted(date: .abbreviated, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))",
                            systemImage: "calendar"
                        )
                        if entry.appleCalendarEventIdentifier != nil {
                            Label("Apple Calendar", systemImage: "checkmark.icloud")
                        }
                        if let lead = entry.reminderLeadMinutes {
                            Label("\(lead) min before", systemImage: "bell")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if entry.calendarStartDate == nil, entry.appleCalendarEventIdentifier != nil {
                    Label("Apple Calendar · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.icloud")
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

                if let audioURL {
                    AudioNotePlayer(url: audioURL)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .contextMenu {
                Button("Edit", systemImage: "pencil", action: onEdit)
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

private struct EditTimelineEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let original: LogEntry
    let onSave: (LogEntry) -> Void

    @State private var title: String
    @State private var note: String
    @State private var timestamp: Date
    @State private var category: LogCategory
    @State private var amount: String
    @State private var duration: String
    @State private var status: EntryStatus
    @State private var lifeArea: LifeArea
    @State private var deviceSource: DeviceSource
    @State private var listKind: ListKind
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var calendarStart: Date
    @State private var calendarEnd: Date

    init(entry: LogEntry, onSave: @escaping (LogEntry) -> Void) {
        original = entry
        self.onSave = onSave
        _title = State(initialValue: entry.title)
        _note = State(initialValue: entry.note)
        _timestamp = State(initialValue: entry.timestamp)
        _category = State(initialValue: entry.category)
        _amount = State(initialValue: entry.amount.map { String(format: "%.2f", $0) } ?? "")
        _duration = State(initialValue: entry.durationMinutes.map(String.init) ?? "")
        _status = State(initialValue: entry.status ?? .inProgress)
        _lifeArea = State(initialValue: entry.lifeArea ?? entry.category.defaultLifeArea)
        _deviceSource = State(initialValue: entry.deviceSource ?? .offline)
        _listKind = State(initialValue: entry.listKind ?? .task)
        _hasDueDate = State(initialValue: entry.dueDate != nil)
        _dueDate = State(initialValue: entry.dueDate ?? .now)
        _calendarStart = State(initialValue: entry.calendarStartDate ?? entry.timestamp)
        _calendarEnd = State(initialValue: entry.calendarEndDate ?? entry.timestamp.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    TextField("Title", text: $title)
                    DatePicker("Time", selection: $timestamp)
                    Picker("Category", selection: $category) {
                        ForEach(LogCategory.allCases) { Text($0.displayName).tag($0) }
                    }
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Details") {
                    if category == .expense || original.amount != nil {
                        TextField("Amount", text: $amount)
                    }
                    TextField("Duration in minutes", text: $duration)
                    if category == .book || category == .movie {
                        Picker("Status", selection: $status) {
                            ForEach(EntryStatus.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Picker("Life area", selection: $lifeArea) {
                        ForEach(LifeArea.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Source", selection: $deviceSource) {
                        ForEach(DeviceSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                if category == .list {
                    Section("List or reminder") {
                        Picker("Type", selection: $listKind) {
                            ForEach(ListKind.allCases) { Text($0.displayName).tag($0) }
                        }
                        Toggle("Add a due date", isOn: $hasDueDate)
                        if hasDueDate { DatePicker("Due", selection: $dueDate) }
                    }
                }

                if original.calendarStartDate != nil {
                    Section {
                        DatePicker("Starts", selection: $calendarStart)
                        DatePicker("Ends", selection: $calendarEnd, in: calendarStart...)
                    } header: {
                        Text("Calendar time")
                    } footer: {
                        if original.appleCalendarEventIdentifier != nil {
                            Text("Saving also updates the linked Apple Calendar event.")
                        }
                    }
                }
            }
            .navigationTitle("Edit entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 560)
    }

    private func save() {
        var updated = original
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.timestamp = timestamp
        updated.category = category
        updated.amount = amount.isEmpty ? nil : Double(amount.replacingOccurrences(of: ",", with: "."))
        updated.durationMinutes = duration.isEmpty ? nil : Int(duration)
        updated.status = category == .book || category == .movie ? status : nil
        updated.lifeArea = lifeArea
        updated.deviceSource = deviceSource
        updated.listKind = category == .list ? listKind : nil
        updated.dueDate = category == .list && hasDueDate ? dueDate : nil
        if original.calendarStartDate != nil {
            updated.calendarStartDate = calendarStart
            updated.calendarEndDate = calendarEnd
        }
        onSave(updated)
        dismiss()
    }
}

private struct AudioNotePlayer: View {
    let url: URL
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        Button(action: togglePlayback) {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                Image(systemName: "waveform")
                Text("Voice note")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause voice note" : "Play voice note")
        .onDisappear {
            player?.stop()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        do {
            if player == nil {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            }
            player?.play()
            isPlaying = true
        } catch {
            isPlaying = false
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
    @State private var photoSuggestion: String?
    @State private var isInterpretingPhoto = false
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
    private var destinationList: AsitraList? {
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
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(model.lists) { list in
                                    Button {
                                        selectedListID = list.id
                                        selectedListKind = list.kind
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: list.kind.systemImage)
                                                    .font(.headline)
                                                Spacer()
                                                Image(systemName: list.access.systemImage)
                                                    .font(.caption)
                                            }
                                            Text(list.name)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Text(list.kind.displayName)
                                                .font(.caption)
                                                .foregroundStyle(
                                                    destinationList?.id == list.id ? Color.white.opacity(0.82) : Color.secondary
                                                )
                                        }
                                        .foregroundStyle(destinationList?.id == list.id ? Color.white : Color.primary)
                                        .padding(12)
                                        .frame(width: 150, alignment: .leading)
                                        .background {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(destinationList?.id == list.id ? Color.accentColor : Color.secondary.opacity(0.09))
                                        }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(destinationList?.id == list.id ? Color.clear : Color.secondary.opacity(0.12))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)

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

                        if isInterpretingPhoto {
                            Label("Interpreting on device…", systemImage: "sparkles")
                                .foregroundStyle(.secondary)
                        } else if let photoSuggestion {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Suggested from photo", systemImage: "checkmark.shield")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(photoSuggestion)
                                    .font(.callout)
                                Button("Use suggestion") { input = photoSuggestion }
                                    .buttonStyle(.borderless)
                            }
                        }
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
                interpretDetailedPhoto(newItem)
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
            timestamp: suggestion.calendarStartDate ?? timestamp,
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
            dueDate: category == .list && hasDueDate ? dueDate : nil,
            calendarStartDate: suggestion.calendarStartDate,
            calendarEndDate: suggestion.calendarEndDate,
            reminderLeadMinutes: suggestion.reminderLeadMinutes
        ), photoData: photoData, syncToCalendar: suggestion.calendarStartDate != nil)
        onSaved()
        dismiss()
    }

    private func interpretDetailedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isInterpretingPhoto = true
        Task {
            defer { isInterpretingPhoto = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            photoData = data
            guard let analysis = try? await ImageIntelligenceService.analyze(data) else { return }
            photoSuggestion = analysis.suggestedCapture
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                input = analysis.suggestedCapture
            }
            if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !analysis.recognizedText.isEmpty {
                note = "Recognized from the attached photo on device:\n\(analysis.recognizedText)"
            }
        }
    }
}
