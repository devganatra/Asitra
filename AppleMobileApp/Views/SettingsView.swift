import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var importMessage: String?
    @State private var importError: String?

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Daily log") {
                Toggle("Daily reminder", isOn: $model.notificationsEnabled)
                Toggle("iCloud sync (not configured)", isOn: $model.syncEnabled)
                    .disabled(true)
            }

            Section("Connections") {
                LabeledContent("Screen Time", value: "Entitlement required")
                LabeledContent("Cross-device sync", value: "CloudKit setup required")
                LabeledContent("Manual capture", value: "Timeline")
                LabeledContent("Apps & sensors", value: "Apple Health")
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
                Text("Entries and photos are currently stored locally. Cross-device sync requires an Apple Developer team and private CloudKit container. Automatic app usage requires Apple approval for the Family Controls entitlement and a Device Activity report extension.")
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
        .alert("Fitness connection", isPresented: Binding(
            get: { importMessage != nil || importError != nil },
            set: { if !$0 { importMessage = nil; importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? importMessage ?? "")
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
