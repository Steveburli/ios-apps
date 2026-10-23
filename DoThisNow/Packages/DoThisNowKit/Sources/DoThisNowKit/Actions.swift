import Foundation

/// "Remind me in…"
public enum SnoozeChoice: String, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes, oneHour, threeHours, tomorrowMorning, threeDays, aWeek

    public var id: Self { self }

    public var label: String {
        switch self {
        case .fifteenMinutes: return "15 min"
        case .oneHour: return "1 hour"
        case .threeHours: return "3 hours"
        case .tomorrowMorning: return "Tomorrow morning"
        case .threeDays: return "3 days"
        case .aWeek: return "A week"
        }
    }

    public func date(from now: Date, wake: Int, calendar: Calendar) -> Date {
        switch self {
        case .fifteenMinutes: return now.addingTimeInterval(15 * 60)
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .threeHours: return now.addingTimeInterval(180 * 60)
        case .threeDays: return now.addingTimeInterval(3 * 86_400)
        case .aWeek: return now.addingTimeInterval(7 * 86_400)
        case .tomorrowMorning:
            return CalendarDay(now, calendar: calendar).adding(days: 1, calendar: calendar)
                .date(atMinute: Double(wake), calendar: calendar)
        }
    }
}

/// "When did you do it?"
public enum DoneWhen: Int, CaseIterable, Identifiable, Sendable {
    case today = 0, fewDaysAgo = 3, lastWeek = 7, coupleWeeksAgo = 14, dontRemember = 30

    public var id: Self { self }

    public var label: String {
        switch self {
        case .today: return "Today"
        case .fewDaysAgo: return "A few days ago"
        case .lastWeek: return "Last week"
        case .coupleWeeksAgo: return "A couple weeks ago"
        case .dontRemember: return "Don’t remember"
        }
    }
}

extension PlannerState {
    // MARK: Sessions

    public mutating func startSession(tasks: [TaskItem], title: String, minutes: Int, at now: Date) {
        active = ActiveSession(taskIDs: tasks.map(\.id), title: title, planned: max(1, minutes),
                               startedAt: now, bundle: tasks.count > 1)
    }

    /// Ends the timer and logs the time. Returns the message to show.
    ///
    /// Finishing a single task also saves how long it took in all, so the
    /// next estimate for anything with that title can learn from it.
    @discardableResult
    public mutating func endSession(finished: Bool, at now: Date) -> String? {
        guard let session = active else { return nil }
        let elapsed = session.elapsed(at: now)
        let minutes = max(1, Int((elapsed / 60).rounded()))
        var message = "Logged"
        if !session.bundle {
            if let id = session.taskIDs.first, let task = self.task(id) {
                if finished && task.kind != .recurring && elapsed >= 60 {
                    timings.append(Timing(title: task.title, start: session.startedAt, seconds: elapsed + Double(task.spent) * 60))
                }
                log.append(LogEntry(taskID: id, at: session.startedAt, minutes: minutes))
                updateTask(id) { t in
                    t.spent += minutes
                    t.lastDone = now
                    if finished && t.kind != .recurring {
                        t.done = true
                        t.doneAt = now
                    }
                }
                message = finished && task.kind != .recurring
                    ? "Done: “\(task.title)”"
                    : "Logged \(TimeText.duration(minutes)) on “\(task.title)”"
            } else if session.taskIDs.isEmpty {
                // A task from Reminders, Google Tasks or the Inbox.
                if finished {
                    if elapsed >= 60 {
                        timings.append(Timing(title: session.title, start: session.startedAt, seconds: elapsed))
                    }
                    if let ref = session.ref, ref.source == .inbox, let index = inboxItems.firstIndex(where: { $0.id == ref.id }) {
                        inboxItems[index].done = true
                        inboxItems[index].doneAt = now
                    }
                    message = "Done: “\(session.title)”"
                } else {
                    message = "Logged \(TimeText.duration(minutes)) on “\(session.title)”"
                }
            }
        } else {
            let left = session.taskIDs.filter { !session.ticked.contains($0) }.compactMap { task($0) }
            if finished {
                for t in left {
                    updateTask(t.id) { t in
                        t.done = true
                        t.doneAt = now
                        t.lastDone = now
                    }
                    log.append(LogEntry(taskID: t.id, at: now, minutes: t.estimate > 0 ? t.estimate : 10))
                }
            }
            message = "Nice. \(session.ticked.count + (finished ? left.count : 0)) crossed off."
        }
        if finished, let blockID = session.blockID {
            updateBlock(blockID) { $0.done = true }
        }
        active = nil
        return message
    }

    public mutating func pauseSession(at now: Date) {
        guard active?.pausedAt == nil else { return }
        active?.pausedAt = now
    }

    public mutating func resumeSession(at now: Date) {
        guard let pausedAt = active?.pausedAt else { return }
        active?.pausedSeconds += now.timeIntervalSince(pausedAt)
        active?.pausedAt = nil
    }

    public mutating func extendSession(by minutes: Int = 15) {
        active?.planned += minutes
        active?.chimed = false
    }

    /// Checks an item off (or back on) during an errand run or sweep.
    public mutating func tick(taskID: String, checked: Bool, at now: Date) {
        guard active != nil, let task = self.task(taskID) else { return }
        if checked {
            if !(active?.ticked.contains(taskID) ?? false) { active?.ticked.append(taskID) }
            updateTask(taskID) { t in
                t.done = true
                t.doneAt = now
                t.lastDone = now
            }
            log.append(LogEntry(taskID: taskID, at: now, minutes: task.estimate > 0 ? task.estimate : 10))
        } else {
            active?.ticked.removeAll { $0 == taskID }
            updateTask(taskID) { t in
                t.done = false
                t.doneAt = nil
            }
        }
    }

    // MARK: The "Do this." card

    /// "Already done": cross it off as of some days ago.
    public mutating func markAlreadyDone(_ candidate: Candidate, when: DoneWhen, now: Date) {
        let date = now.addingTimeInterval(-Double(when.rawValue) * 86_400)
        for t in candidate.tasks {
            if t.kind == .recurring {
                let minutes = candidate.tasks.count == 1 ? candidate.minutes : (t.estimate > 0 ? t.estimate : 15)
                log.append(LogEntry(taskID: t.id, at: date, minutes: minutes))
                updateTask(t.id) { $0.lastDone = max($0.lastDone ?? .distantPast, date) }
            } else {
                updateTask(t.id) { task in
                    task.done = true
                    task.doneAt = date
                    task.lastDone = date
                }
            }
        }
    }

    public mutating func snooze(_ taskIDs: [String], until date: Date) {
        for id in taskIDs {
            updateTask(id) { task in
                task.snoozeUntil = date
                task.remindSeen = false
            }
        }
    }

    public mutating func clearReminder(_ id: String) {
        updateTask(id) { task in
            task.remindSeen = true
            task.snoozeUntil = nil
        }
    }

    // MARK: Lists

    public mutating func deleteTask(_ id: String) {
        tasks.removeAll { $0.id == id }
        log.removeAll { $0.taskID == id }
        blocks.removeAll { $0.ref == SourceRef(.app, id) && !$0.done }
    }

    /// Ticks off every block waiting on a task, when the task gets done some other way.
    public mutating func finishBlocks(for ref: SourceRef) {
        for index in blocks.indices where blocks[index].ref == ref {
            blocks[index].done = true
        }
    }

    public mutating func deleteEvent(_ id: String) {
        events.removeAll { $0.id == id }
    }

    public mutating func restore(_ id: String, now: Date) {
        updateTask(id) { task in
            task.done = false
            task.archived = false
            task.doneAt = nil
            task.nudgeUntil = now.addingTimeInterval(14 * 86_400)
        }
    }

    /// Applies a drag-to-reorder: the active tasks in their new order and tiers.
    public mutating func applyOrder(_ rows: [(id: String, tier: Int)]) {
        var ordered: [TaskItem] = []
        var seen = Set<String>()
        for row in rows {
            guard var task = self.task(row.id), !seen.contains(row.id) else { continue }
            task.tier = row.tier
            ordered.append(task)
            seen.insert(row.id)
        }
        tasks = ordered + tasks.filter { !seen.contains($0.id) }
    }

    public mutating func eraseEverything() {
        self = PlannerState()
    }

    // MARK: Check-ins

    /// "Yes, push me on it". Returns the new tier.
    @discardableResult
    public mutating func nudgeSerious(_ id: String, now: Date) -> Int? {
        updateTask(id) { task in
            task.nudgeUntil = now.addingTimeInterval(30 * 86_400)
            if task.tier > 1 { task.tier -= 1 }
        }
        return task(id)?.tier
    }

    /// "Lower its priority". Returns the new tier.
    @discardableResult
    public mutating func nudgeLower(_ id: String, now: Date) -> Int? {
        updateTask(id) { task in
            task.nudgeUntil = now.addingTimeInterval(60 * 86_400)
            if task.tier < 4 { task.tier += 1 }
        }
        return task(id)?.tier
    }

    public mutating func letGo(_ id: String, now: Date) {
        updateTask(id) { task in
            task.archived = true
            task.doneAt = now
        }
    }

    public mutating func loosenGoal(_ id: String, to weekly: Int, now: Date) {
        updateTask(id) { task in
            if weekly > 0 { task.weekly = weekly }
            task.nudgeUntil = now.addingTimeInterval(21 * 86_400)
        }
    }

    /// "I’m serious, keep it" (21 days) or "Remind me next week" (7 days).
    public mutating func quietNudge(_ id: String, days: Int, now: Date) {
        updateTask(id) { $0.nudgeUntil = now.addingTimeInterval(Double(days) * 86_400) }
    }
}
