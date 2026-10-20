import SwiftUI

@main
struct OMMApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.screen {
            case .home:
                HomeView()
            case .workout:
                if let session = model.session {
                    WorkoutView(session: session)
                }
            case .complete(let days):
                CompletionView(days: days)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.session?.refresh() }
        }
    }
}
