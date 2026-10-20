import Foundation
import UserNotifications
import DoThisNowKit

/// Local notifications for what the web app could only show when it was
/// open: the end of a timed session, and tasks you asked to be reminded about.
enum Notifier {
    private static let sessionID = "session-end"
    private static let reminderPrefix = "reminder-"
    /// iOS keeps 64 pending notifications per app.
    private static let reminderLimit = 40

    static func requestPermission() {
        // No permission prompt over the screenshots.
        guard !Screenshots.isActive else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedules (or clears) everything to match the saved state.
    static func sync(_ state: PlannerState, now: Date) {
        let center = UNUserNotificationCenter.current()

        center.removePendingNotificationRequests(withIdentifiers: [sessionID])
        if let session = state.active, !session.chimed, let endsAt = session.endsAt, endsAt > now {
            let content = UNMutableNotificationContent()
            content.title = "Time’s up"
            content.body = "You planned \(TimeText.duration(session.planned)) for “\(session.title)”. Keep going, or call it here?"
            content.sound = .default
            add(center, id: sessionID, content: content, at: endsAt, now: now)
        }

        center.removePendingNotificationRequests(withIdentifiers: state.tasks.map { reminderPrefix + $0.id })
        let upcoming = state.activeTasks
            .compactMap { task in task.snoozeUntil.map { (task, $0) } }
            .filter { $0.1 > now }
            .sorted { $0.1 < $1.1 }
            .prefix(reminderLimit)
        for (task, date) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = "Reminder"
            content.body = "You asked me to bring back “\(task.title)”."
            content.sound = .default
            add(center, id: reminderPrefix + task.id, content: content, at: date, now: now)
        }
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, content: UNNotificationContent, at date: Date, now: Date) {
        let interval = date.timeIntervalSince(now)
        guard interval >= 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { _ in }
    }
}
