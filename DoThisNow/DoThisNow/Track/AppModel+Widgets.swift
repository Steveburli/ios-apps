import SwiftUI
import DoThisNowKit

/// Keeps the widgets, the Lock Screen and the Dynamic Island in step with
/// the Track timer and the Now tab's session.
extension AppModel {
    private static let widgetButtonsKey = "widgetActivityIDs"
    /// Small widgets show two buttons, medium ones four.
    static let widgetButtonLimit = 4

    /// The activities picked in Settings for the start buttons, or nil if
    /// none were ever picked (then the first four on Track are used).
    var widgetActivityIDs: [String]? {
        UserDefaults.standard.stringArray(forKey: Self.widgetButtonsKey)
    }

    func setWidgetActivities(_ ids: [String]) {
        UserDefaults.standard.set(Array(ids.prefix(Self.widgetButtonLimit)), forKey: Self.widgetButtonsKey)
        syncTimers()
    }

    /// The start buttons, in Track order.
    var widgetActivities: [Activity] {
        guard let picked = widgetActivityIDs else { return Array(state.activities.prefix(Self.widgetButtonLimit)) }
        return Array(state.activities.filter { picked.contains($0.id) }.prefix(Self.widgetButtonLimit))
    }

    /// Called after every change: writes what the widgets show and updates
    /// the Live Activities.
    func syncTimers() {
        guard !Screenshots.isActive else { return }
        let running = state.running.map { run in
            TimerBridge.Run(activityID: run.activityID, title: run.title,
                            symbol: state.activity(run.activityID)?.symbol ?? "timer", startedAt: run.startedAt)
        }
        let buttons = widgetActivities.map { TimerBridge.StartButton(id: $0.id, name: $0.name, symbol: $0.symbol) }
        TimerBridge.write(TimerBridge.Snapshot(running: running, buttons: buttons, ready: true))

        let session = state.active.map { session in
            TimerActivityAttributes.ContentState(
                title: session.title, symbol: "bolt.fill", startedAt: session.startedAt, endsAt: session.endsAt,
                pausedRemaining: session.pausedAt == nil ? nil
                    : max(0, TimeInterval(session.planned * 60) - session.elapsed(at: Date())))
        }
        Task {
            await LiveTimers.showTrack(running)
            await LiveTimers.show(.session, session)
        }
    }

    /// A button on a widget or the Lock Screen, run inside the app.
    func handleTimerCommand(_ command: TimerBridge.Command) {
        let saved = apply(command)
        commit()
        if let saved { show("\(saved.title): \(TimeText.clock(saved.seconds)) saved") }
    }

    /// Buttons tapped while the app couldn't run them, replayed with the
    /// times they were tapped.
    func takeTimerCommands() {
        guard !Screenshots.isActive, TimerBridge.hasCommands else { return }
        let commands = TimerBridge.takeCommands()
        guard !commands.isEmpty else { return }
        for command in commands {
            apply(command)
        }
        commit()
    }

    @discardableResult
    private func apply(_ command: TimerBridge.Command) -> Timing? {
        switch command {
        case .stop(let at):
            return state.stopTimer(at: at)
        case .toggle(let id, let at):
            if state.running?.activityID == id {
                return state.stopTimer(at: at)
            }
            guard let activity = state.activity(id) else { return nil }
            return state.startTimer(activityID: id, title: activity.name, at: at)
        }
    }
}
