import SwiftUI
import SwiftData

@main
struct AppleMobileApp: App {
    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        let container = PersistenceController.makeContainer()
        let environment = AppEnvironment.live(container: container)
        self.container = container
        _model = State(initialValue: AppModel(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.timelineFeature)
                .environment(model.calendarFeature)
                .environment(model.healthFeature)
                .environment(model.systemFeature)
                .modelContainer(container)
        }
    }
}
