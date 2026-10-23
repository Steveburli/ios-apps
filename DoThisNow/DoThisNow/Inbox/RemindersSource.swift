import EventKit
import DoThisNowKit

/// Apple Reminders, read with EventKit. Ticking a block off ticks off the reminder.
/// Not tied to the main thread, because EventKit answers on its own queue.
final class RemindersSource: @unchecked Sendable {
    static let shared = RemindersSource()

    private let store = EKEventStore()

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    func lists() -> [AppModel.SourceList] {
        store.calendars(for: .reminder)
            .map { AppModel.SourceList(id: $0.calendarIdentifier, name: $0.title) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every reminder that isn't done yet. The Inbox's filters pick from these.
    func fetch() async -> [SourceTask] {
        guard isAuthorized else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let calendar = Calendar.current
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let tasks = (reminders ?? []).map { reminder in
                    SourceTask(ref: SourceRef(.reminders, reminder.calendarItemIdentifier),
                               title: reminder.title ?? "",
                               notes: reminder.notes ?? "",
                               listID: reminder.calendar?.calendarIdentifier ?? "",
                               listName: reminder.calendar?.title ?? "",
                               due: reminder.dueDateComponents.flatMap { calendar.date(from: $0) },
                               priority: Self.priority(reminder.priority))
                }
                continuation.resume(returning: tasks.filter { !$0.title.isEmpty })
            }
        }
    }

    func complete(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
    }

    /// Reminders uses 1–4 for high, 5 for medium and 6–9 for low.
    static func priority(_ value: Int) -> Int {
        switch value {
        case 1...4: return 3
        case 5: return 2
        case 6...9: return 1
        default: return 0
        }
    }
}
