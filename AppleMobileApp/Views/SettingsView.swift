import AuthenticationServices
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var importMessage: String?
    @State private var importError: String?
    @State private var confirmation: DataConfirmation?
    @State private var dataMessage: String?
    @State private var aiAccount = SakhyaAIAccount.shared

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Daily log") {
                Toggle("Daily reminder", isOn: $model.notificationsEnabled)
            }

            Section("iCloud") {
                Toggle("Sync across my Apple devices", isOn: $model.syncEnabled)
                    .onChange(of: model.syncEnabled) { _, enabled in
                        if enabled { Task { await model.syncNow() } }
                    }

                HStack {
                    LabeledContent("Status", value: model.cloudStatus)
                    if model.isSyncingCloud {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Sync now") { Task { await model.syncNow() } }
                            .disabled(!model.syncEnabled)
                    }
                }
                if let lastSync = model.lastCloudSync {
                    LabeledContent("Last sync", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                }
                Text("Sakhya stores one encrypted-in-transit snapshot in your private CloudKit database. Only devices signed into your iCloud account can access it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Demo data") {
                LabeledContent("Sample timeline", value: "\(model.sampleEntryCount) entries")
                if model.sampleEntryCount == 0 {
                    Button("Add 30 days of sample data") { model.addSampleData() }
                } else {
                    Button("Remove sample data", role: .destructive) { confirmation = .removeSamples }
                }
                Text("Sample entries cover sleep, habits, food, work, expenses, fitness, screen time, mood, books, movies and lists. They are marked internally, so you can remove them without touching your own entries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Data management") {
                LabeledContent("On this device", value: model.localStorageDescription)
                Toggle("Keep deleted entries in Recently Deleted", isOn: $model.keepsDeletedEntries)

                NavigationLink {
                    RecentlyDeletedView()
                } label: {
                    LabeledContent("Recently Deleted", value: "\(model.recentlyDeleted.count)")
                }

                Button("Clear this device, keep iCloud", role: .destructive) {
                    confirmation = .clearLocal
                }
                Button("Delete all data everywhere", role: .destructive) {
                    confirmation = .deleteEverywhere
                }

                Text("Nothing is deleted automatically. Turning off Recently Deleted makes future deletions permanent; existing deleted entries remain until you restore or empty them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Connections") {
                LabeledContent("Screen Time", value: "Entitlement required")
                LabeledContent("Cross-device sync", value: "Private CloudKit")
                LabeledContent("Manual capture", value: "Timeline")
                LabeledContent("Apps & sensors", value: "Apple Health")
            }

            Section("Sakhya AI") {
                LabeledContent("Model", value: aiAccount.modelIdentifier ?? aiAccount.modelLabel)
                LabeledContent("Status", value: aiAccount.isConnected ? "Connected" : "Offline insights")

                if aiAccount.isConnected {
                    Button("Disconnect AI account", role: .destructive) {
                        Task { await aiAccount.disconnect() }
                    }
                } else {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        Task { await aiAccount.completeAppleAuthorization(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 42)
                    .disabled(aiAccount.isConnecting)
                }

                if aiAccount.isConnecting {
                    ProgressView("Connecting Sakhya AI…")
                }
                if let error = aiAccount.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Text("The shared Sakhya model runs through the secure backend, so Mac, iPhone, iPad and web use the same model contract. Sakhya sends calculated metrics with their source, not your complete database. The session is stored in Keychain and can be removed here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Reminders") {
                Toggle("Add Sakhya reminders to Apple Reminders", isOn: $model.appleRemindersEnabled)

                HStack {
                    LabeledContent("Status", value: model.appleRemindersStatus)
                    if model.appleRemindersStatus != "Connected" {
                        Button("Connect") {
                            Task { await model.connectAppleReminders() }
                        }
                    }
                }

                if let error = model.appleRemindersError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("New reminder entries are created in your default Apple Reminders list with their due date and alert. Completing or deleting them in Sakhya updates the linked Apple reminder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Calendar") {
                Toggle("Mirror every new entry to Apple Calendar", isOn: $model.appleCalendarEnabled)
                HStack {
                    LabeledContent("Status", value: model.appleCalendarStatus)
                    if model.appleCalendarStatus != "Connected" {
                        Button("Connect") { Task { await model.connectAppleCalendar() } }
                    }
                }
                Text("Every personal entry is mirrored to Apple Calendar. Scheduled phrases use their detected range; ordinary entries use the logged time and tracked duration, or a 15-minute block. Sample data is never exported. Add “remind me 30 minutes before” to also create a linked Apple Reminder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Fitness & Health") {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    if model.isImportingFitness {
                        ProgressView()
                    } else {
                        Button(model.lastFitnessImport == nil ? "Connect" : "Sync now") {
                            importHealthData()
                        }
#if os(macOS)
                        .disabled(true)
#endif
                    }
                }

                if let lastImport = model.lastFitnessImport {
                    LabeledContent("Last synced", value: lastImport.formatted(date: .abbreviated, time: .shortened))
                }

                if !model.connectedFitnessSources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sources in your timeline")
                            .font(.subheadline.weight(.semibold))
                        ForEach(model.connectedFitnessSources, id: \.self) { source in
                            Label(source, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                LabeledContent {
                    Text("Via Apple Health")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("WHOOP", systemImage: "waveform.path.ecg")
                }

                Text("Sakhya imports workouts and sleep from Apple Health and preserves the app or device that recorded each item. Enable Health sharing in WHOOP or another fitness app, then sync here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("A direct WHOOP connection will require a registered WHOOP developer app and secure OAuth token service.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

#if os(macOS)
                Text("Apple Health permission must be connected on iPhone or iPad.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
#endif
            }

            Section {
                Text("The app always keeps a local working copy. iCloud sync requires selecting your Apple Developer team and enabling the iCloud.com.devganatra.sakhya container in Xcode. Automatic app usage requires Apple approval for the Family Controls entitlement and a Device Activity report extension.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Platform", value: platformName)
                LabeledContent("App", value: "Sakhya")
                LabeledContent("Version", value: "0.1")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task {
            await aiAccount.refreshModelContract()
        }
        .alert("Fitness connection", isPresented: Binding(
            get: { importMessage != nil || importError != nil },
            set: { if !$0 { importMessage = nil; importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? importMessage ?? "")
        }
        .confirmationDialog(confirmation?.title ?? "", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), titleVisibility: .visible) {
            if let confirmation {
                Button(confirmation.actionTitle, role: .destructive) { perform(confirmation) }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: {
            Text(confirmation?.message ?? "")
        }
        .alert("Data management", isPresented: Binding(
            get: { dataMessage != nil },
            set: { if !$0 { dataMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dataMessage ?? "")
        }
    }

    private func perform(_ action: DataConfirmation) {
        confirmation = nil
        switch action {
        case .removeSamples:
            model.removeSampleData()
        case .clearLocal:
            model.clearLocalCopyKeepingCloud()
            dataMessage = "The local copy was cleared and iCloud was kept. Sync was turned off to prevent an immediate restore."
        case .deleteEverywhere:
            Task {
                do {
                    try await model.deleteEverywhere()
                    dataMessage = "The local and iCloud copies were deleted."
                } catch {
                    dataMessage = "Nothing was removed locally because the iCloud copy could not be deleted: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importHealthData() {
        Task {
            do {
                let count = try await model.importFitnessData()
                importMessage = count == 0
                    ? "Your timeline is already up to date."
                    : "Added \(count) workout and sleep entries to your timeline."
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private var platformName: String {
#if os(macOS)
        "Mac"
#elseif os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
#else
        "Apple device"
#endif
    }
}

private enum DataConfirmation: String, Identifiable {
    case removeSamples, clearLocal, deleteEverywhere
    var id: String { rawValue }
    var title: String {
        switch self {
        case .removeSamples: "Remove sample data?"
        case .clearLocal: "Clear this device?"
        case .deleteEverywhere: "Delete all Sakhya data?"
        }
    }
    var actionTitle: String {
        switch self {
        case .removeSamples: "Remove Sample Data"
        case .clearLocal: "Clear This Device"
        case .deleteEverywhere: "Delete Everywhere"
        }
    }
    var message: String {
        switch self {
        case .removeSamples: "Only entries created as sample data will be removed. Your entries will stay."
        case .clearLocal: "Entries and attachments on this device will be removed. Your iCloud copy will stay, and sync will be turned off."
        case .deleteEverywhere: "This permanently removes the Sakhya snapshot from iCloud and all entries and attachments on this device. This cannot be undone."
        }
    }
}

private struct RecentlyDeletedView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEmpty = false

    var body: some View {
        List {
            if model.recentlyDeleted.isEmpty {
                ContentUnavailableView("Nothing Deleted", systemImage: "trash", description: Text("Deleted entries can stay here until you decide what to do."))
            } else {
                Section {
                    ForEach(model.recentlyDeleted) { deleted in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(deleted.entry.title).font(.headline)
                            Text("Deleted \(deleted.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Restore") { model.restore(deleted) }
                                .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Sakhya never empties this list automatically.")
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .toolbar {
            if !model.recentlyDeleted.isEmpty {
                ToolbarItemGroup {
                    Button("Restore All") { model.restoreAllDeleted() }
                    Button("Empty", role: .destructive) { confirmEmpty = true }
                }
            }
        }
        .confirmationDialog("Permanently delete these entries?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) { model.emptyRecentlyDeleted() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes their local photo and voice attachments and cannot be undone.")
        }
    }
}
