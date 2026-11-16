import Foundation

/// The "To place" queue: tasks sent to a day without a time yet (from the
/// week view, or by pressing and holding a task). They wait at the top of
/// that day until you drag them onto the timeline. New in the app only.
extension PlannerState {
    /// The tasks waiting on `day`, in the order they were sent.
    public func queue(on day: CalendarDay) -> [SourceRef] {
        dayConfig(day).queue
    }

    /// Every task waiting in a queue from `day` on. Like a block, a queued
    /// task is planned, so the Inbox leaves it out. A queue on a day that has
    /// passed is dropped by `prune`, and its tasks come back to the Inbox.
    public func queuedKeys(from day: CalendarDay) -> Set<String> {
        var keys = Set<String>()
        for (key, config) in days where !config.queue.isEmpty {
            guard let queued = CalendarDay(key: key), queued >= day else { continue }
            keys.formUnion(config.queue.map(\.key))
        }
        return keys
    }

    /// The day a task is waiting on, if any.
    public func queuedDay(for key: String) -> CalendarDay? {
        days.compactMap { dayKey, config in
            config.queue.contains { $0.key == key } ? CalendarDay(key: dayKey) : nil
        }.min()
    }

    /// Sends a task to `day` with no time: it leaves any other day's queue
    /// and any block still waiting for it from `today` on, and joins the end
    /// of `day`'s queue.
    public mutating func sendToDay(_ ref: SourceRef, _ day: CalendarDay, today: CalendarDay) {
        removeFromQueues(ref.key)
        blocks.removeAll { $0.ref == ref && !$0.done && $0.day >= today }
        updateDay(day) { $0.queue.append(ref) }
    }

    /// Takes a task out of every queue: it got a time, or went back to the Inbox.
    public mutating func removeFromQueues(_ key: String) {
        for (dayKey, config) in days where config.queue.contains(where: { $0.key == key }) {
            days[dayKey]?.queue.removeAll { $0.key == key }
        }
    }
}

extension Engine {
    /// The tasks waiting on `day`, as Inbox rows. Tasks that were finished,
    /// deleted or snoozed meanwhile drop out.
    public func queued(on day: CalendarDay, external: [SourceTask] = []) -> [InboxEntry] {
        let refs = state.queue(on: day)
        guard !refs.isEmpty else { return [] }
        var byKey: [String: SourceTask] = [:]
        for task in appSourceTasks() + inboxSourceTasks() + external where byKey[task.id] == nil {
            byKey[task.id] = task
        }
        let hidden = Set(state.inbox.hidden)
        return refs.compactMap { ref in
            guard !hidden.contains(ref.key), let task = byKey[ref.key] else { return nil }
            return InboxEntry(task: task, estimate: estimate(for: task))
        }
    }
}
