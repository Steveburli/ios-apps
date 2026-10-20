import UserNotifications

/// A local notification for when rest runs out while the phone is locked or
/// another app is open. In the foreground the chime plays instead.
enum RestNotifier {
    private static let identifier = "rest-timer"

    static func requestPermission() {
        // No permission prompt over the screenshots.
        guard !Screenshots.isActive else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(after seconds: Int, title: String, body: String) {
        guard seconds > 0, !Screenshots.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
