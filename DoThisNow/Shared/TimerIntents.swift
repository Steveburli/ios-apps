import AppIntents
import Foundation

// The buttons on the widgets and the Lock Screen. They're LiveActivityIntents,
// so iOS runs them inside the app (in the background, without opening it)
// where it can; otherwise TimerControl falls back to the shared files.

/// Starts timing an activity, or stops it if it's the one running.
struct ToggleTrackTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start or stop a Track timer"
    static var description = IntentDescription("Starts timing a Do This Now activity, or stops it if it’s already running.")
    static var isDiscoverable = false

    @Parameter(title: "Activity")
    var activityID: String

    init() {}

    init(activityID: String) {
        self.activityID = activityID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await TimerControl.run(.toggle(activityID, at: Date()))
        return .result()
    }
}

/// Stops the Track timer and saves the time.
struct StopTrackTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop the Track timer"
    static var description = IntentDescription("Stops the running Do This Now Track timer and saves the time.")
    static var isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TimerControl.run(.stop(at: Date()))
        return .result()
    }
}
