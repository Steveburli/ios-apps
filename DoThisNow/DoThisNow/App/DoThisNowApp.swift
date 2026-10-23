import SwiftUI
import UIKit
import EventKit
import DoThisNowKit

@main
struct DoThisNowApp: App {
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
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Screen { NowView() }
                .tabItem { Label("Now", systemImage: "bolt.fill") }
                .tag(AppModel.Tab.now)
            Screen { TasksView() }
                .tabItem { Label("Tasks", systemImage: "list.bullet") }
                .badge(model.engine.nudges().count)
                .tag(AppModel.Tab.tasks)
            Screen { DayView() }
                .tabItem { Label("Day", systemImage: "calendar.day.timeline.left") }
                .tag(AppModel.Tab.day)
            Screen { TrackView() }
                .tabItem { Label("Track", systemImage: "stopwatch") }
                .tag(AppModel.Tab.track)
            Screen { WakeView() }
                .tabItem { Label("Wake", systemImage: "alarm") }
                .tag(AppModel.Tab.wake)
        }
        .tint(Theme.accent)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .sheet(item: $model.sheet) { sheet in
            SheetContent(sheet: sheet)
                .environment(model)
        }
        .fullScreenCover(item: $model.scanMode) { mode in
            ScanView(mode: mode)
                .environment(model)
        }
        .onReceive(clock) { model.tick($0) }
        .onReceive(NotificationCenter.default.publisher(for: InboxDropbox.arrived)) { _ in
            model.takeDroppedTasks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await model.refreshSources() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.tick(Date())
                model.takeDroppedTasks()
                model.syncAlarms()
                Task { await model.refreshSources() }
            }
        }
        .onChange(of: model.tab) { _, tab in
            if tab == .day {
                model.openDayTab()
                Task { await model.refreshSources() }
            }
        }
        .task { await model.refreshSources() }
    }
}

/// Each tab's navigation bar: the brand in the middle, Settings on the right.
private struct Screen<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .background(Theme.bg.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Theme.accentWash, lineWidth: 3))
                            Text("Do this now")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.ink)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.sheet = .settings
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Theme.ink2)
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .toolbarBackground(Theme.bg, for: .navigationBar)
        }
    }
}

private struct SheetContent: View {
    @Environment(AppModel.self) private var model
    let sheet: AppModel.Sheet

    var body: some View {
        switch sheet {
        case .newTask:
            TaskFormView(task: nil)
        case .editTask(let id):
            TaskFormView(task: model.state.task(id))
        case .newEvent(let day):
            EventFormView(event: nil, day: day)
        case .editEvent(let id):
            EventFormView(event: model.state.events.first { $0.id == id }, day: model.dayShown)
        case .settings:
            SettingsView()
        case .dayItem(let id):
            DayItemSheet(chunkID: id)
        case .meal:
            MealSheet()
        case .schedule(let key):
            ScheduleSheet(key: key)
        case .block(let id):
            BlockSheet(blockID: id)
        case .inboxSettings:
            InboxSettingsView()
        case .activity(let id):
            ActivitySheet(activityID: id)
        case .newActivity:
            ActivityFormView(activity: nil)
        case .timing(let id):
            TimingFormView(timing: model.state.timings.first { $0.id == id }, activityID: nil)
        case .newTiming(let activityID):
            TimingFormView(timing: nil, activityID: activityID)
        case .routineStep(let id):
            RoutineStepForm(stepID: id)
        case .sleep:
            SleepSettingsForm()
        case .alarm:
            AlarmSettingsView()
        }
    }
}

private struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: AppModel.Toast

    var body: some View {
        Text(toast.message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.bg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.updatesFrequently)
            .task(id: toast.id) {
                UIAccessibility.post(notification: .announcement, argument: toast.message)
                try? await Task.sleep(for: .seconds(2.8))
                model.clearToast(toast.id)
            }
    }
}
