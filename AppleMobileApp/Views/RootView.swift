import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(AppSection.allCases, selection: $model.selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Sakhya")
        } detail: {
            destination(for: model.selectedSection ?? .today)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .today:
            HomeView()
        case .lists:
            ListsView()
        case .balance:
            BalanceView()
        case .collections:
            LibraryView()
        case .insights:
            InsightsView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
