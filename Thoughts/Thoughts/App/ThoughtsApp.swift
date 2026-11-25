import SwiftUI
import ThoughtsKit

@main
struct ThoughtsApp: App {
    @State private var model: AppModel = Screenshots.isActive ? Screenshots.makeModel() : AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.appearance.scheme)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $model.homePath) {
                    HomeView()
                        .pageDestinations()
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                NavigationStack(path: $model.searchPath) {
                    SearchView()
                        .pageDestinations()
                }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack(path: $model.settingsPath) {
                    SettingsView()
                        .pageDestinations()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveNow() }
        }
        .onAppear { Screenshots.prepare(model) }
    }
}

extension View {
    /// Every tab opens pages the same way.
    func pageDestinations() -> some View {
        navigationDestination(for: UUID.self) { id in
            PageScreen(pageID: id)
        }
    }
}
