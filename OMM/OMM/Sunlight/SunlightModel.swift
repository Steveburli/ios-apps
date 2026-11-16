import Foundation
import Observation
import UserNotifications
import OMMKit

/// The daily sunlight goal: the "I'm outside" timer, logged time and the
/// reminders to go outside. Saved as JSON under `sunlight.v1`, apart from the
/// program, so Reset Program keeps it.
@Observable
@MainActor
final class SunlightModel {
    /// The sheet that asks what kind of light it was: after "Back inside", or to add time by hand.
    enum Sheet: Identifiable {
        case finish
        case add

        var id: Self { self }
    }

    private(set) var log: SunlightLog
    var sheet: Sheet?
    var showingSettings = false

    @ObservationIgnored private let defaults: UserDefaults
    private nonisolated static let key = "sunlight.v1"
    private nonisolated static let goalNotice = "sunlight-goal"

    init(defaults: UserDefaults = .standard) {
        if Screenshots.isActive {
            self.defaults = UserDefaults(suiteName: "screenshots") ?? defaults
            log = Screenshots.sampleSunlight()
            switch Screenshots.screen {
            case "sunlight": sheet = .finish
            case "sunlightsettings": showingSettings = true
            default: break
            }
            return
        }
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(SunlightLog.self, from: data) {
            log = saved
        } else {
            log = SunlightLog()
        }
    }

    // MARK: Timer

    func goOutside() {
        log.startOutside(at: Date())
        save()
        scheduleGoalNotice()
        rescheduleReminders()
    }

    /// "Back inside": asks what kind of light it was, then logs it.
    func comeInside() {
        guard log.isOutside else { return }
        sheet = .finish
    }

    func finish(kind: SunlightKind, minutes: Int) {
        log.stopOutside(at: Date(), kind: kind, minutes: minutes)
        sheet = nil
        cancelGoalNotice()
        save()
        rescheduleReminders()
    }

    /// Throws the running timer away without logging.
    func discardTimer() {
        log.cancelOutside()
        sheet = nil
        cancelGoalNotice()
        save()
        rescheduleReminders()
    }

    func add(minutes: Int, kind: SunlightKind) {
        log.add(minutes: minutes, kind: kind, endingAt: Date())
        sheet = nil
        save()
        rescheduleReminders()
    }

    func remove(_ entry: SunlightEntry) {
        log.remove(entry.id)
        save()
        rescheduleReminders()
    }

    // MARK: Settings

    var goalMinutes: Int {
        get { log.goalMinutes }
        set {
            log.setGoal(newValue)
            save()
            rescheduleReminders()
        }
    }

    var remindersOn: Bool {
        get { log.remindersOn }
        set {
            log.remindersOn = newValue
            save()
            if newValue { requestPermission() }
            rescheduleReminders()
        }
    }

    func setTime(_ date: Date, for kind: SunlightReminder.Kind) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        switch kind {
        case .morning: log.morning = time
        case .midday: log.midday = time
        case .lastCall: log.lastCall = time
        }
        save()
        rescheduleReminders()
    }

    func time(for kind: SunlightReminder.Kind) -> Date {
        let time: TimeOfDay
        switch kind {
        case .morning: time = log.morning
        case .midday: time = log.midday
        case .lastCall: time = log.lastCall
        }
        return time.date(on: Date()) ?? Date()
    }

    // MARK: Notifications

    /// Re-plans the week's reminders. Runs whenever time is logged and when the app comes forward.
    func rescheduleReminders() {
        guard !Screenshots.isActive else { return }
        let reminders = SunlightReminders.plan(for: log, now: Date())
        let center = UNUserNotificationCenter.current()
        let goalNotice = Self.goalNotice
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix("sunlight-") && $0 != goalNotice }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for reminder in reminders {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)) { _ in }
            }
        }
    }

    /// While the timer runs, a notification for when today's goal is reached (counting it as open sky).
    private func scheduleGoalNotice() {
        guard !Screenshots.isActive, log.isOutside else { return }
        let left = log.goalMinutes - log.minutesToday(now: Date())
        guard left > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Sunlight goal reached"
        content.body = "That's \(log.goalMinutes) min today if you were under open sky. Tap Back inside when you head in."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(left * 60), repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: Self.goalNotice, content: content, trigger: trigger)) { _ in }
        requestPermission()
    }

    private func cancelGoalNotice() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.goalNotice])
        center.removeDeliveredNotifications(withIdentifiers: [Self.goalNotice])
    }

    private func requestPermission() {
        guard !Screenshots.isActive else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func save() {
        guard !Screenshots.isActive else { return }
        log.prune(now: Date())
        if let data = try? JSONEncoder().encode(log) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
