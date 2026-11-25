import SwiftUI
import LittlesKit

@main
struct LittlesApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.accent)
        }
    }
}

enum AppTab: Hashable {
    case today, food, play, schedule, grow
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: AppTab = Screenshots.tab
    @State private var showWelcome = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            FoodView()
                .tabItem { Label("Food", systemImage: "carrot.fill") }
                .tag(AppTab.food)
            PlayView()
                .tabItem { Label("Play", systemImage: "puzzlepiece.fill") }
                .tag(AppTab.play)
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(AppTab.schedule)
            GrowView()
                .tabItem { Label("Grow", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.grow)
        }
        .onAppear {
            showWelcome = Screenshots.shows("welcome") || (!Screenshots.isActive && !model.state.onboarded)
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView { showWelcome = false }
                .environmentObject(model)
        }
    }
}
