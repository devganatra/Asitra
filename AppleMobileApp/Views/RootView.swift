import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAssistant = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(AppSection.allCases, selection: $model.selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Asitra")
        } detail: {
            destination(for: model.selectedSection ?? .today)
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            Button {
                showingAssistant = true
            } label: {
                Label("Ask Asitra", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.14))
                    }
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .accessibilityLabel("Ask Asitra")
            .help("Ask Asitra about your stats")
        }
        .sheet(isPresented: $showingAssistant) {
            AssistantChatView()
                .environment(model)
        }
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .today:
            HomeView()
        case .tasks:
            TasksView()
        case .lists:
            ListsView()
        case .money:
            ExpensesView()
        case .balance:
            BalanceView()
        case .collections:
            LibraryView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel(container: PersistenceController.makeContainer(inMemory: true)))
}
