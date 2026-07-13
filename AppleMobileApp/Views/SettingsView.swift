import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(AppModel.self) private var model

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
            }

            Section {
                Text("Entries and photos are currently stored locally. Cross-device sync requires an Apple Developer team and private CloudKit container. Automatic app usage requires Apple approval for the Family Controls entitlement and a Device Activity report extension.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Platform", value: platformName)
                LabeledContent("App", value: "Dayline")
                LabeledContent("Version", value: "0.1")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
