import Foundation
import UserNotifications
import LittlesKit

/// Local reminders for routines that ask for one ("Pickup in 20 minutes").
/// Each routine gets a weekly repeating notification per weekday.
enum Notifier {
    private static let prefix = "routine-"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sync(_ state: FamilyState) {
        let center = UNUserNotificationCenter.current()
        var requests: [UNNotificationRequest] = []
        for routine in state.routines {
            guard let remind = routine.remind else { continue }
            let at = routine.start - remind
            for weekday in routine.weekdays {
                // A reminder before midnight belongs to the day before.
                var day = weekday
                var minutes = at
                if minutes < 0 {
                    minutes += 1440
                    day = day == 1 ? 7 : day - 1
                }
                var components = DateComponents()
                components.weekday = day
                components.hour = minutes / 60
                components.minute = minutes % 60
                let content = UNMutableNotificationContent()
                let who = names(routine.kidIDs, in: state)
                content.title = routine.title + (who.isEmpty ? "" : " · " + who)
                content.body = remind == 0
                    ? "Now" + (routine.place.isEmpty ? "" : " at \(routine.place)")
                    : "In \(remind) minutes, at \(Dates.clock(routine.start))" + (routine.place.isEmpty ? "" : " · \(routine.place)")
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                requests.append(UNNotificationRequest(identifier: "\(prefix)\(routine.id)-\(weekday)", content: content, trigger: trigger))
            }
        }
        let wanted = requests
        center.getPendingNotificationRequests { pending in
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: old)
            for request in wanted { center.add(request) }
        }
    }

    private static func names(_ ids: [String], in state: FamilyState) -> String {
        if ids.isEmpty { return "" }
        return ids.compactMap { state.kid($0)?.name }.joined(separator: " & ")
    }
}
