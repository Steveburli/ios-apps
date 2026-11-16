import Foundation

/// Something to do on a break that isn't a task, like a walk or a
/// 10-minute meditation, with its usual length.
public struct BreakIdea: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var minutes: Int
    /// An SF Symbol name.
    public var symbol = "sparkles"

    public init(id: String = newID(), name: String, minutes: Int, symbol: String = "sparkles") {
        self.id = id
        self.name = name
        self.minutes = max(1, minutes)
        self.symbol = symbol
    }

    private enum CodingKeys: String, CodingKey { case id, name, minutes, symbol }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  minutes: try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 10,
                  symbol: try c.decodeIfPresent(String.self, forKey: .symbol) ?? "sparkles")
    }

    /// The list you start with. You can change all of it.
    public static let starters: [BreakIdea] = [
        BreakIdea(id: "idea-walk", name: "Walk around the park", minutes: 20, symbol: "figure.walk"),
        BreakIdea(id: "idea-workout", name: "Workout", minutes: 15, symbol: "figure.strengthtraining.traditional"),
        BreakIdea(id: "idea-meditate", name: "Meditate", minutes: 10, symbol: "brain.head.profile"),
        BreakIdea(id: "idea-stretch", name: "Stretch", minutes: 5, symbol: "figure.flexibility"),
        BreakIdea(id: "idea-coffee", name: "Make a coffee", minutes: 10, symbol: "cup.and.saucer"),
        BreakIdea(id: "idea-read", name: "Read a chapter", minutes: 20, symbol: "book"),
    ]
}

/// The focus timer: while it runs, break time builds up.
public struct FocusRun: Codable, Equatable, Sendable {
    public var startedAt: Date
    /// When you last said you were still working (or started). Time more
    /// than `BreakBank.checkAfter` past this doesn't count until you say so.
    public var checkedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
        checkedAt = startedAt
    }
}

/// A break you're on, spending the balance.
public struct BreakRun: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var minutes: Int

    public init(startedAt: Date, minutes: Int) {
        self.startedAt = startedAt
        self.minutes = max(1, minutes)
    }

    public var endsAt: Date {
        startedAt.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Seconds spent so far. A break stops spending when it's over.
    public func spent(at now: Date) -> TimeInterval {
        min(max(0, now.timeIntervalSince(startedAt)), TimeInterval(minutes * 60))
    }
}

/// Break time earned by focused work. Every `PlannerSettings.workPerBreak`
/// minutes of work earns one minute of break. You can take a break you
/// haven't fully earned: the balance goes below zero and the next work pays
/// it back. Earned time left over at the end of a day is gone the next
/// morning, but time you owe carries over.
public struct BreakBank: Codable, Equatable, Sendable {
    /// Ask "Still working?" after this long without a check.
    public static let checkAfter: TimeInterval = 90 * 60

    /// The day `seconds` belongs to.
    public var day: CalendarDay?
    /// Break seconds in the bank. Below zero is time owed.
    public var seconds: Double = 0
    public var focus: FocusRun?
    public var current: BreakRun?
    public var ideas: [BreakIdea] = BreakIdea.starters

    public init() {}

    private enum CodingKeys: String, CodingKey { case day, seconds, focus, current, ideas }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(CalendarDay.self, forKey: .day)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        focus = try c.decodeIfPresent(FocusRun.self, forKey: .focus)
        current = try c.decodeIfPresent(BreakRun.self, forKey: .current)
        ideas = try c.decodeIfPresent([BreakIdea].self, forKey: .ideas) ?? BreakIdea.starters
    }
}

/// A break idea that fits the time you have, and how many times over.
public struct BreakFit: Equatable, Sendable {
    public let idea: BreakIdea
    /// Its usual length: your Track timings if you've timed it, else the idea's own.
    public let minutes: Int
    public let times: Int
}

extension PlannerState {
    /// Break seconds earned by this much work.
    public func breakEarned(forWork seconds: Double) -> Double {
        max(0, seconds) / Double(max(1, settings.workPerBreak))
    }

    /// Work seconds the focus timer has counted. Past 90 minutes without a
    /// "Still working?" yes, it stops counting.
    public func focusWork(at now: Date) -> Double {
        guard let focus = breaks.focus else { return 0 }
        let end = min(now, focus.checkedAt.addingTimeInterval(BreakBank.checkAfter))
        return max(0, end.timeIntervalSince(focus.startedAt))
    }

    /// The focus timer has run 90 minutes since you last said you were working.
    public func needsStillWorking(at now: Date) -> Bool {
        guard let focus = breaks.focus else { return false }
        return now >= focus.checkedAt.addingTimeInterval(BreakBank.checkAfter)
    }

    /// Break seconds you have right now, counting the focus timer and the
    /// break you're on. Below zero is time owed.
    public func breakBalance(at now: Date, calendar: Calendar) -> Double {
        var seconds = breaks.seconds
        if let day = breaks.day, day != CalendarDay(now, calendar: calendar), seconds > 0 { seconds = 0 }
        seconds += breakEarned(forWork: focusWork(at: now))
        if let current = breaks.current { seconds -= current.spent(at: now) }
        return seconds
    }

    /// Whole minutes of break you can take: rounded down, never below zero.
    public func breakMinutesAvailable(at now: Date, calendar: Calendar) -> Int {
        max(0, Int((breakBalance(at: now, calendar: calendar) / 60).rounded(.down)))
    }

    /// A new day starts at zero. Time owed is kept.
    mutating func rollBreakDay(at now: Date, calendar: Calendar) {
        let today = CalendarDay(now, calendar: calendar)
        guard breaks.day != today else { return }
        if breaks.day != nil, breaks.seconds > 0 { breaks.seconds = 0 }
        breaks.day = today
    }

    // MARK: Focus

    /// Starts the focus timer. Ends a break you're on, keeping what's left.
    public mutating func startFocus(at now: Date, calendar: Calendar) {
        endBreak(at: now, calendar: calendar)
        guard breaks.focus == nil else { return }
        rollBreakDay(at: now, calendar: calendar)
        breaks.focus = FocusRun(startedAt: now)
    }

    /// "Still working?" "Yes": everything so far counts, and the next check is 90 minutes away.
    public mutating func confirmStillWorking(at now: Date) {
        breaks.focus?.checkedAt = now
    }

    /// Stops the focus timer and banks what it earned. Returns the break
    /// seconds earned, or nil if it wasn't running. Saves the run on Track
    /// as "Focus" when it lasted a minute or more.
    @discardableResult
    public mutating func stopFocus(at now: Date, calendar: Calendar) -> Double? {
        guard let focus = breaks.focus else { return nil }
        let work = focusWork(at: now)
        breaks.focus = nil
        rollBreakDay(at: now, calendar: calendar)
        let earned = breakEarned(forWork: work)
        breaks.seconds += earned
        if work >= 60 {
            timings.append(Timing(title: "Focus", start: focus.startedAt, seconds: work))
        }
        return earned
    }

    /// Banks break time for a timed session from the Now tab. Nothing is
    /// added while the focus timer runs (it's already counting) or while
    /// you're on a break. Returns the break seconds earned.
    @discardableResult
    public mutating func earnBreak(forWork seconds: Double, at now: Date, calendar: Calendar) -> Double {
        guard breaks.focus == nil, breaks.current == nil, seconds > 0 else { return 0 }
        rollBreakDay(at: now, calendar: calendar)
        let earned = breakEarned(forWork: seconds)
        breaks.seconds += earned
        return earned
    }

    // MARK: Breaks

    /// Starts a break of this many minutes. It can be longer than what
    /// you've earned. Stops the focus timer first, banking what it earned.
    public mutating func startBreak(minutes: Int, at now: Date, calendar: Calendar) {
        stopFocus(at: now, calendar: calendar)
        endBreak(at: now, calendar: calendar)
        rollBreakDay(at: now, calendar: calendar)
        breaks.current = BreakRun(startedAt: now, minutes: minutes)
    }

    /// Ends the break, early or on time. Only the time taken is spent.
    /// Returns the seconds spent, or nil if there was no break.
    @discardableResult
    public mutating func endBreak(at now: Date, calendar: Calendar) -> Double? {
        guard let current = breaks.current else { return nil }
        breaks.current = nil
        rollBreakDay(at: now, calendar: calendar)
        let spent = current.spent(at: now)
        breaks.seconds -= spent
        return spent
    }

    // MARK: Ideas

    /// Break ideas that fit this many minutes, longest first. An idea you've
    /// timed on Track uses your usual time for it.
    public func breakFits(minutes available: Int) -> [BreakFit] {
        guard available > 0 else { return [] }
        let fits = breaks.ideas.compactMap { idea -> BreakFit? in
            let usual = estimate(title: idea.name, source: idea.minutes).minutes
            let times = available / usual
            return times >= 1 ? BreakFit(idea: idea, minutes: usual, times: times) : nil
        }
        return fits.stableSorted(by: { $0.minutes > $1.minutes })
    }
}
