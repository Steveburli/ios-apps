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
        @Bindable var model = model
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.screen {
            case .home:
                HomeView()
            case .workout:
                if let session = model.session {
                    if session.phase == .cardio {
                        CardioView(session: session)
                    } else {
                        WorkoutView(session: session)
                    }
                }
            case .stretch:
                if let stretch = model.stretch {
                    StretchView(session: stretch)
                }
            case .complete(let days):
                CompletionView(days: days)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshTimers() }
        }
        .fullScreenCover(isPresented: $model.isEnteringWeights) {
            if let session = model.session {
                WeightEntryView(session: session)
                    .environment(model)
            }
        }
    }
}
