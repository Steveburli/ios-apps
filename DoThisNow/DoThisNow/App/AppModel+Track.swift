import SwiftUI
import DoThisNowKit

/// The Track tab: timing the things you do often.
extension AppModel {
    /// Tap an activity to time it; tap it again to stop. Tapping another one
    /// saves the first and starts the next, so a whole routine is one tap each.
    func tapActivity(_ id: String) {
        guard let activity = state.activity(id) else { return }
        let now = Date()
        let saved: Timing?
        if state.running?.activityID == id {
            saved = state.stopTimer(at: now)
        } else {
            saved = state.startTimer(activityID: id, title: activity.name, at: now)
        }
        commit()
        if let saved {
            show("\(saved.title): \(TimeText.clock(saved.seconds)) saved")
        }
    }

    func stopTimer() {
        let saved = state.stopTimer(at: Date())
        commit()
        if let saved { show("\(saved.title): \(TimeText.clock(saved.seconds)) saved") }
    }

    func save(_ activity: Activity) {
        let name = activity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var activity = activity
        activity.name = name
        activity.aliases = activity.aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let index = state.activities.firstIndex(where: { $0.id == activity.id }) {
            state.activities[index] = activity
        } else {
            state.activities.append(activity)
        }
        sheet = nil
        commit()
    }

    func deleteActivity(_ id: String) {
        let name = state.activity(id)?.name ?? ""
        state.deleteActivity(id)
        sheet = nil
        commit()
        show("Deleted “\(name)” and its timings")
    }

    func moveActivities(from source: IndexSet, to destination: Int) {
        state.activities.move(fromOffsets: source, toOffset: destination)
        commit()
    }

    func save(_ timing: Timing) {
        if let index = state.timings.firstIndex(where: { $0.id == timing.id }) {
            state.timings[index] = timing
        } else {
            state.timings.append(timing)
        }
        sheet = nil
        commit()
    }

    func deleteTiming(_ id: String) {
        state.timings.removeAll { $0.id == id }
        sheet = nil
        commit()
    }

    /// An activity for a routine step or Inbox task, made if there isn't one.
    func activityID(for title: String) -> String {
        if let existing = state.activity(matching: title) { return existing.id }
        let activity = Activity(name: title.trimmingCharacters(in: .whitespacesAndNewlines))
        state.activities.append(activity)
        return activity.id
    }
}

extension TimeText {
    /// "4:05" or "1:02:30".
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
