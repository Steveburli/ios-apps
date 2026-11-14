import SwiftUI

/// The bottom tabs. Other OMM tabs add a case here and a `Tab` below.
enum AppTab: Hashable {
    case workout
    case stretch
}

/// The home screens behind the tab bar. A workout, a stretch routine and the
/// completion screen still take the whole screen, outside the tabs.
struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Workout", systemImage: "dumbbell.fill", value: AppTab.workout) {
                onGradient { HomeView() }
            }
            Tab("Stretch", systemImage: "figure.flexibility", value: AppTab.stretch) {
                onGradient { StretchTabView() }
            }
        }
        .tint(Theme.primary)
    }

    private func onGradient<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content()
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color.white, for: .tabBar)
    }
}
