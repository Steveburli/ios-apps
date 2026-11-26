import SwiftUI
import LittlesKit

@main
struct LittlesApp: App {
    @StateObject private var model = AppModel.shared

    init() {
        LittlesShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.accent)
                .onOpenURL { url in
                    // A family file from the other phone (AirDrop, Messages, Files).
                    if url.pathExtension.lowercased() == "littles" { model.importSync(from: url) }
                }
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
    @State private var minute = Dates.minutes(Date())
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let night = model.state.settings.nightMode.isActive(minute: minute) || Screenshots.shows("night")
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
        // Night mode: dark, dimmed and red-shifted for 3 AM feeds.
        .preferredColorScheme(night ? .dark : nil)
        .colorMultiply(night ? Color(red: 1, green: 0.42, blue: 0.32) : .white)
        .brightness(night ? -0.08 : 0)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                Text(banner)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                    .onTapGesture { model.banner = nil }
                    .task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        model.banner = nil
                    }
            }
        }
        .onReceive(clock) { _ in minute = Dates.minutes(Date()) }
        .onAppear {
            showWelcome = Screenshots.shows("welcome") || (!Screenshots.isActive && !model.state.onboarded)
            if !Screenshots.isActive { Notifier.requestPermission() }
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView { showWelcome = false }
                .environmentObject(model)
        }
    }
}
