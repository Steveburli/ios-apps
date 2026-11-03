import UserNotifications

/// A local notification for when a countdown (rest, cardio or a stretch) runs
/// out while the phone is locked or another app is open. In the foreground the
/// chime plays instead. Only one countdown runs at a time, so one id covers all.
enum RestNotifier {
    private static let identifier = "rest-timer"

    static func requestPermission() {
        // No permission prompt over the screenshots.
        guard !Screenshots.isActive else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(after seconds: TimeInterval, title: String, body: String) {
        guard seconds >= 1, !Screenshots.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
