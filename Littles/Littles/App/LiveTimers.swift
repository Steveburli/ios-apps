import Foundation
import ActivityKit
import LittlesKit

/// Keeps one Live Activity per running sleep or nursing timer: starts it when
/// a timer starts, ends it when the timer stops.
enum LiveTimers {
    @MainActor
    static func sync(_ state: FamilyState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !Screenshots.isActive else { return }
        let running = state.logs.filter { $0.isRunning }
        let runningIDs = Set(running.map { $0.id })
        let current = Activity<TimerActivityAttributes>.activities
        for activity in current where !runningIDs.contains(activity.attributes.entryID) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let shown = Set(current.map { $0.attributes.entryID })
        for entry in running where !shown.contains(entry.id) {
            guard let kid = state.kid(entry.kidID) else { continue }
            let attributes = TimerActivityAttributes(entryID: entry.id, kidName: kid.name,
                                                     emoji: entry.kind.emoji,
                                                     activity: entry.kind == .sleep ? "asleep" : "nursing",
                                                     color: Int(Theme.kidHex[((kid.color % Theme.kidHex.count) + Theme.kidHex.count) % Theme.kidHex.count]))
            let content = ActivityContent(state: TimerActivityAttributes.ContentState(start: entry.start, detail: entry.side?.title ?? ""),
                                          staleDate: nil)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }
}
