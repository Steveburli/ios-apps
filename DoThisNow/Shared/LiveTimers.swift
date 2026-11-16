import Foundation
import ActivityKit

/// A timer on the Lock Screen and in the Dynamic Island: a Track timer
/// counting up, or the Now tab's session counting down.
struct TimerActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable {
        case track, session
    }

    struct ContentState: Codable, Hashable {
        var title: String
        /// An SF Symbol name.
        var symbol: String
        /// When it started; a Track timer counts up from here.
        var startedAt: Date
        /// A running session counts down to this.
        var endsAt: Date?
        /// A paused session: the seconds left, frozen.
        var pausedRemaining: TimeInterval?
    }

    var kind: Kind
}

extension TimerActivityAttributes.ContentState {
    init(_ run: TimerBridge.Run) {
        self.init(title: run.title, symbol: run.symbol, startedAt: run.startedAt, endsAt: nil, pausedRemaining: nil)
    }
}

/// Starts, updates and ends the Live Activities so they match the app.
@MainActor
enum LiveTimers {
    private static var queue: Task<Void, Never>?

    static func showTrack(_ run: TimerBridge.Run?) async {
        await show(.track, run.map(TimerActivityAttributes.ContentState.init))
    }

    /// Shows `state` for that kind of timer, or ends it when nil. Calls run
    /// one after another, so two quick changes never start two activities.
    static func show(_ kind: TimerActivityAttributes.Kind, _ state: TimerActivityAttributes.ContentState?) async {
        #if WIDGET_EXTENSION
        // Only the app can start or end Live Activities.
        return
        #else
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await apply(kind, state)
        }
        queue = task
        await task.value
        #endif
    }

    #if !WIDGET_EXTENSION
    private static func apply(_ kind: TimerActivityAttributes.Kind, _ state: TimerActivityAttributes.ContentState?) async {
        let existing = ActivityKit.Activity<TimerActivityAttributes>.activities.filter { $0.attributes.kind == kind }
        guard let state else {
            for activity in existing {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        if let current = existing.first {
            for extra in existing.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            if current.content.state != state {
                await current.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? ActivityKit.Activity<TimerActivityAttributes>.request(
            attributes: TimerActivityAttributes(kind: kind),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil)
    }
    #endif
}
