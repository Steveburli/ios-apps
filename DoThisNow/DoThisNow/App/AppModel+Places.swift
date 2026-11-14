import SwiftUI
import UserNotifications
import DoThisNowKit

/// Track timers that start and stop by place.
extension AppModel {
    /// One model for the app, so a place crossing that relaunches the app in
    /// the background reaches the same state the screens use.
    static let shared = AppModel()

    /// The phone crossed a watched place's edge: run its rules, save, and say what happened.
    func placeCrossed(_ placeID: String, _ crossing: PlaceCrossing, at time: Date) {
        let fired = state.crossed(placeID: placeID, crossing, at: time)
        guard !fired.isEmpty else { return }
        commit()
        for firing in fired {
            PlaceNotices.fired(firing, formats: formats)
        }
        if let last = fired.last {
            show(last.summary)
        }
    }

    func undoPlaceFiring(_ id: String) {
        guard let firing = state.placeTimers.history.first(where: { $0.id == id }) else { return }
        if state.undo(firingID: id) {
            commit()
            PlaceNotices.clear(firingID: id)
            show("Undone: \(firing.title) \(firing.action == .start ? "isn’t running" : "is still running")")
        } else {
            show("Can’t undo that now: the timer has changed since.")
        }
    }

    /// "Still running?" → Stop.
    func stopCheckedTimer() {
        guard state.placeCheckDue != nil else { return }
        stopTimer()
    }

    /// "Still running?" → Keep going: ask again in an hour.
    func keepCheckedTimer() {
        state.postponePlaceCheck(from: Date())
        commit()
    }

    func save(_ place: WatchedPlace) {
        if let index = state.placeTimers.places.firstIndex(where: { $0.id == place.id }) {
            state.placeTimers.places[index] = place
        } else {
            state.placeTimers.places.append(place)
        }
        placesChanged()
    }

    func deleteWatchedPlace(_ id: String) {
        state.deleteWatchedPlace(id)
        placesChanged()
    }

    func save(_ rule: PlaceRule) {
        let isNew: Bool
        if let index = state.placeTimers.rules.firstIndex(where: { $0.id == rule.id }) {
            state.placeTimers.rules[index] = rule
            isNew = false
        } else {
            state.placeTimers.rules.append(rule)
            isNew = true
        }
        placesChanged()
        // A new rule is the moment to ask for "Always". If it's switched off,
        // the Places screen and the Track tab say so instead.
        if isNew, !PlaceWatcher.shared.isAlways, !PlaceWatcher.shared.isOff {
            PlaceWatcher.shared.requestAlways()
        }
    }

    func deletePlaceRule(_ id: String) {
        state.placeTimers.rules.removeAll { $0.id == id }
        placesChanged()
    }

    /// Home, the gym and two rules, for the screenshots.
    func loadPlaceExample() {
        let gym = Activity(name: "Gym", symbol: "dumbbell")
        state.activities.append(gym)
        let home = WatchedPlace(name: "Home", address: "Where you were when you added it",
                                coordinate: Coordinate(latitude: 39.7684, longitude: -86.1581))
        let club = WatchedPlace(name: "Gym", address: "1 Monument Cir, Indianapolis",
                                coordinate: Coordinate(latitude: 39.7685, longitude: -86.1580), radius: 250)
        state.placeTimers.places = [home, club]
        state.placeTimers.rules = [
            PlaceRule(activityID: gym.id, action: .start, crossing: .leave, placeID: home.id),
            PlaceRule(activityID: gym.id, action: .stop, crossing: .leave, placeID: club.id),
        ]
        let yesterday = now.addingTimeInterval(-86_400)
        state.crossed(placeID: home.id, .leave, at: yesterday)
        state.crossed(placeID: club.id, .leave, at: yesterday.addingTimeInterval(80 * 60))
        state.crossed(placeID: home.id, .leave, at: now.addingTimeInterval(-20 * 60))
    }

    private func placesChanged() {
        commit()
        PlaceWatcher.shared.sync(state.placeTimers.watchedPlaces)
    }
}

/// The notifications for place rules: "Gym started" with Undo, and "Still
/// timing Gym?" an hour after a rule started a timer.
enum PlaceNotices {
    static let firedCategory = "place-fired"
    static let checkCategory = "place-check"
    static let undoAction = "place-undo"
    static let stopAction = "place-stop"
    static let keepAction = "place-keep"
    private static let checkID = "place-check"
    private static let firedPrefix = "place-fired-"

    static func registerCategories() {
        let undo = UNNotificationAction(identifier: undoAction, title: "Undo", options: [])
        let stop = UNNotificationAction(identifier: stopAction, title: "Stop it", options: [])
        let keep = UNNotificationAction(identifier: keepAction, title: "Keep going", options: [])
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            var categories = existing.filter { $0.identifier != firedCategory && $0.identifier != checkCategory }
            categories.insert(UNNotificationCategory(identifier: firedCategory, actions: [undo], intentIdentifiers: []))
            categories.insert(UNNotificationCategory(identifier: checkCategory, actions: [stop, keep], intentIdentifiers: []))
            center.setNotificationCategories(categories)
        }
    }

    /// A quiet note right away: "Gym started at 6:02 when you left Home."
    static func fired(_ firing: PlaceFiring, formats: Formats) {
        let content = UNMutableNotificationContent()
        content.title = "\(firing.title) \(firing.action == .start ? "started" : "stopped")"
        content.body = "At \(formats.time(firing.at)), when you \(firing.crossing == .arrive ? "got to" : "left") \(firing.placeName)."
        content.categoryIdentifier = firedCategory
        content.userInfo = ["firing": firing.id]
        content.interruptionLevel = .active
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: firedPrefix + firing.id, content: content, trigger: nil)) { _ in }
    }

    static func clear(firingID: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [firedPrefix + firingID])
    }

    /// Called from `Notifier.sync` after every change.
    static func sync(_ state: PlannerState, now: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [checkID])
        guard let due = state.placeCheckDue, let running = state.running else { return }
        let content = UNMutableNotificationContent()
        content.title = "Still timing \(running.title)?"
        let minutes = max(1, Int(due.timeIntervalSince(running.startedAt) / 60))
        content.body = "It’s been running \(TimeText.duration(minutes)) since a place rule started it. Stop it, or keep going?"
        content.categoryIdentifier = checkCategory
        content.sound = .default
        let interval = max(1, due.timeIntervalSince(now))
        center.add(UNNotificationRequest(identifier: checkID, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))) { _ in }
    }
}

/// Handles the buttons on place-rule notifications, even when they wake the
/// app in the background.
final class NotificationActions: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationActions()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The app shows its own toast for place rules while open; everything
        // else keeps the old behavior of not showing over the open app.
        completionHandler([])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let firingID = response.notification.request.content.userInfo["firing"] as? String
        let isPlace = response.notification.request.content.categoryIdentifier.hasPrefix("place-")
        Task { @MainActor in
            let model = AppModel.shared
            switch action {
            case PlaceNotices.undoAction:
                if let firingID { model.undoPlaceFiring(firingID) }
            case PlaceNotices.stopAction:
                model.stopCheckedTimer()
            case PlaceNotices.keepAction:
                model.keepCheckedTimer()
            default:
                if isPlace {
                    model.tab = .track
                }
            }
            completionHandler()
        }
    }
}
