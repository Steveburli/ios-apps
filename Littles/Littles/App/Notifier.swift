import Foundation
import UserNotifications
import LittlesKit

/// Local reminders, rebuilt after every change:
/// - routines that ask for one ("Pickup in 20 minutes"), weekly
/// - "Leave for school in 15 minutes", with the pack list, for the next 7 school days
/// - potty training reminders for today and tomorrow
/// - "Next dose of ibuprofen is OK now"
/// - a week before the next checkup
enum Notifier {
    private static let prefix = "littles-"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sync(_ state: FamilyState, now: Date = Date()) {
        var requests: [UNNotificationRequest] = []
        let calendar = Dates.calendar

        func content(_ title: String, _ body: String) -> UNMutableNotificationContent {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            return content
        }
        func once(_ id: String, at date: Date, _ content: UNMutableNotificationContent) {
            guard date > now else { return }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            requests.append(UNNotificationRequest(identifier: prefix + id, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }

        // Routines, weekly.
        for routine in state.routines {
            guard let remind = routine.remind else { continue }
            for weekday in routine.weekdays {
                var day = weekday
                var minutes = routine.start - remind
                if minutes < 0 {
                    minutes += 1440
                    day = day == 1 ? 7 : day - 1
                }
                var parts = DateComponents()
                parts.weekday = day
                parts.hour = minutes / 60
                parts.minute = minutes % 60
                let who = names(routine.kidIDs, in: state)
                let body = remind == 0
                    ? "Now" + (routine.place.isEmpty ? "" : " at \(routine.place)")
                    : "In \(remind) minutes, at \(Dates.clock(routine.start))" + (routine.place.isEmpty ? "" : " · \(routine.place)")
                requests.append(UNNotificationRequest(identifier: "\(prefix)routine-\(routine.id)-\(weekday)",
                                                      content: content(routine.title + (who.isEmpty ? "" : " · " + who), body),
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)))
            }
        }

        let today = Dates.key(now, calendar: calendar)

        // Leave for school.
        if state.settings.countdown {
            for offset in 0..<7 {
                let day = Dates.addDays(today, offset, calendar: calendar)
                guard let leave = Agenda.leave(on: day, state: state, travelMinutes: state.settings.travelMinutes, calendar: calendar),
                      let at = Dates.at(day, minutes: leave.minute - 15, calendar: calendar) else { continue }
                let pack = Agenda.packList(on: day, state: state, calendar: calendar).map { $0.title }
                let body = "Leave at \(Dates.clock(leave.minute)) for \(leave.entry.title.lowercased())." + (pack.isEmpty ? "" : " Pack: " + pack.joined(separator: ", ") + ".")
                once("leave-\(day)", at: at, content("Leave in 15 minutes", body))
            }
        }

        // Potty training, today and tomorrow.
        for (kidID, plan) in state.settings.potty where plan.on {
            guard let kid = state.kid(kidID) else { continue }
            for offset in 0..<2 {
                let day = Dates.addDays(today, offset, calendar: calendar)
                for minute in plan.times {
                    if let at = Dates.at(day, minutes: minute, calendar: calendar) {
                        once("potty-\(kidID)-\(day)-\(minute)", at: at, content("Potty time 🚽", "Time for \(kid.name) to try the potty."))
                    }
                }
            }
        }

        // Medicine.
        if state.settings.medicineReminders {
            for kid in state.kids {
                for status in MedicineTimer.status(state.logs, kidID: kid.id, now: now) {
                    once("med-\(kid.id)-\(status.rule.id)", at: status.nextOK,
                         content("\(kid.name): next \(status.rule.name.components(separatedBy: " (").first ?? "dose") OK",
                                 "It's been long enough since the last dose, if \(kid.name) still needs it."))
                }
            }
        }

        // Checkups, a week ahead at 9 AM.
        if state.settings.checkupReminders {
            for kid in state.kids {
                guard let next = HealthSchedule.nextCheckup(birthday: kid.birthday, today: today, calendar: calendar),
                      let at = Dates.at(Dates.addDays(next.1, -7, calendar: calendar), minutes: 9 * 60, calendar: calendar) else { continue }
                once("checkup-\(kid.id)-\(next.0.months)", at: at,
                     content("\(kid.name)'s \(next.0.title) checkup", "Due around \(next.1). Time to book it if you haven't."))
            }
        }

        // iOS keeps 64 pending at most: the soonest first.
        let wanted = Array(requests.prefix(64))
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix("littles-") || $0.hasPrefix("routine-") }
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
