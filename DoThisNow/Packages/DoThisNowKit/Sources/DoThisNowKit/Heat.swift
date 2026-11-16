import Foundation

/// How hot a task is, from cold (blue, 0) to hot (red, 1). New in the app
/// only: the web app has no heat colors.
///
/// Heat comes from the task's tier, how close its deadline is, and how many
/// times you pressed Not now on it. Once a deadline has passed the task is
/// "angry": fully hot, and a little bigger each day late, up to 5 days.
public struct TaskHeat: Equatable, Sendable {
    /// 0 (cold) to 1 (hot).
    public let value: Double
    /// Whole days past the deadline, 0 when it isn't late.
    public let daysLate: Int

    /// Days late after which an angry task stops growing.
    public static let maxGrowthDays = 5

    public init(value: Double, daysLate: Int = 0) {
        self.value = min(1, max(0, value))
        self.daysLate = max(0, daysLate)
    }

    public var isAngry: Bool { daysLate > 0 }

    /// How much bigger to draw an angry task: 1 when on time, growing by a
    /// tenth a day late, and stopping at 1.5.
    public var scale: Double {
        1 + 0.1 * Double(min(daysLate, Self.maxGrowthDays))
    }

    /// 0 when on time, 1 once it has stopped growing.
    public var anger: Double {
        Double(min(daysLate, Self.maxGrowthDays)) / Double(Self.maxGrowthDays)
    }

    static func tierPart(_ tier: Int) -> Double {
        switch tier {
        case 1: return 0.5
        case 2: return 0.35
        case 3: return 0.2
        default: return 0.05
        }
    }

    /// Each Not now adds this much, for up to `maxSnoozes` presses.
    static let perSnooze = 0.07
    static let maxSnoozes = 5

    /// Heat from a tier, a deadline and a snooze count.
    public static func of(tier: Int, deadline: CalendarDay?, snoozes: Int, today: CalendarDay,
                          calendar: Calendar) -> TaskHeat {
        var value = tierPart(tier) + perSnooze * Double(min(max(snoozes, 0), maxSnoozes))
        guard let deadline else { return TaskHeat(value: value) }
        let days = today.days(until: deadline, calendar: calendar)
        if days < 0 { return TaskHeat(value: 1, daysLate: -days) }
        // Due today adds the most; two weeks or more out adds nothing.
        value += 0.45 * max(0, 1 - Double(days) / 14)
        return TaskHeat(value: value)
    }
}

extension TaskItem {
    public func heat(today: CalendarDay, calendar: Calendar) -> TaskHeat {
        TaskHeat.of(tier: tier, deadline: deadline, snoozes: snoozes, today: today, calendar: calendar)
    }

    /// A new, later deadline is a fresh start: the heat earned from snoozes
    /// goes away. Moving it earlier, or taking it off, keeps the heat.
    public mutating func coolIfDeadlineMovedLater(from old: CalendarDay?) {
        guard let new = deadline, new != old else { return }
        if old == nil || new > old! { snoozes = 0 }
    }
}

extension SourceTask {
    /// Heat for a task that isn't in the app's own list, from its due date
    /// and its source's priority.
    public func heat(today: CalendarDay, calendar: Calendar) -> TaskHeat {
        TaskHeat.of(tier: Tier.forReminder(priority: priority), deadline: due.map { CalendarDay($0, calendar: calendar) },
                    snoozes: 0, today: today, calendar: calendar)
    }
}

extension PlannerState {
    /// The app task behind a block or an Inbox row: one of its own, or the
    /// one that mirrors a reminder.
    public func task(for ref: SourceRef) -> TaskItem? {
        switch ref.source {
        case .app: return task(ref.id)
        case .reminders: return tasks.first { $0.reminderID == ref.id }
        default: return nil
        }
    }
}
