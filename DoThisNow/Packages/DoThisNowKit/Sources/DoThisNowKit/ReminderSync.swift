import Foundation

/// Apple Reminders as real tasks. Each reminder that passes your filters gets
/// a task, so Now, Tasks and the Day all see it. Finishing it on either side
/// finishes it on the other.
extension Tier {
    /// Where a new reminder starts. 0 none, 1 low, 2 medium, 3 high.
    public static func forReminder(priority: Int) -> Int {
        switch priority {
        case 3: return 1
        case 2: return 2
        default: return 3
        }
    }
}

extension PlannerState {
    /// Brings tasks in line with every open reminder. Only call this with a
    /// list that was read successfully: a reminder missing from it counts as
    /// ticked off or deleted.
    public mutating func syncReminders(_ open: [SourceTask], now: Date, calendar: Calendar) {
        let today = CalendarDay(now, calendar: calendar)
        let filter = inbox.reminders
        let hidden = Set(inbox.hidden)
        let openIDs = Set(open.map(\.ref.id))
        let wanted = filter.on ? open.filter { !hidden.contains($0.id) && filter.allows($0, today: today, calendar: calendar) } : []
        let wantedIDs = Set(wanted.map(\.ref.id))
        let underway = Set(active?.taskIDs ?? [])

        for task in tasks {
            guard let reminderID = task.reminderID else { continue }
            if !openIDs.contains(reminderID) {
                // Ticked off or deleted over in Reminders.
                updateTask(task.id) { t in
                    t.reminderClosed = true
                    if t.isActive {
                        t.done = true
                        t.doneAt = now
                        t.lastDone = now
                    }
                }
                if task.isActive { finishBlocks(for: SourceRef(.app, task.id)) }
            } else if !wantedIDs.contains(reminderID) && task.isActive && !underway.contains(task.id) {
                // Filtered out. It comes back if the filters change, and the reminder stays put.
                tasks.removeAll { $0.id == task.id }
                blocks.removeAll { $0.ref == SourceRef(.app, task.id) && !$0.done }
            }
        }

        for reminder in wanted {
            if let task = tasks.first(where: { $0.reminderID == reminder.ref.id }) {
                // Let go, or finished here and not yet ticked off there.
                guard !task.archived, !task.done || task.reminderClosed else { continue }
                if let label = listLabel(forList: reminder.listID) {
                    noteSharedChange(task: task, reminder: reminder, label: label, now: now)
                }
                updateTask(task.id) { t in
                    t.reminderPriority = reminder.priority
                    if t.done {
                        // Open again over there: unticked, or a repeating reminder's next round.
                        t.done = false
                        t.doneAt = nil
                    }
                    t.reminderClosed = false
                    t.reminderListID = reminder.listID
                    t.title = reminder.title
                    t.notes = reminder.notes
                    let before = t.deadline
                    t.deadline = reminder.due.map { CalendarDay($0, calendar: calendar) }
                    t.coolIfDeadlineMovedLater(from: before)
                }
            } else {
                var task = TaskItem(title: reminder.title, created: now)
                task.reminderID = reminder.ref.id
                task.reminderListID = reminder.listID
                task.notes = reminder.notes
                task.tier = Tier.forReminder(priority: reminder.priority)
                task.reminderPriority = reminder.priority
                task.places = [.anywhere]
                task.deadline = reminder.due.map { CalendarDay($0, calendar: calendar) }
                task.estimate = estimate(title: reminder.title).minutes
                tasks.append(task)
            }
        }
        pruneSuggestions()
    }

    /// Finished here and still open in Reminders.
    public var remindersToClose: [TaskItem] {
        tasks.filter { $0.reminderID != nil && $0.done && !$0.reminderClosed }
    }

    /// Brought back here and still ticked off in Reminders.
    public var remindersToReopen: [TaskItem] {
        tasks.filter { $0.reminderID != nil && !$0.done && !$0.archived && $0.reminderClosed }
    }
}

extension PlannerState {
    /// The label of the Reminders list a task came from, such as "From my wife".
    public func listLabel(for task: TaskItem) -> String? {
        guard let list = task.reminderListID,
              let label = inbox.listLabels[list]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }
        return label
    }

    /// The label for a task anywhere a block or Inbox row points at it.
    public func listLabel(for ref: SourceRef) -> String? {
        guard ref.source == .app, let task = task(ref.id) else { return nil }
        return listLabel(for: task)
    }
}
