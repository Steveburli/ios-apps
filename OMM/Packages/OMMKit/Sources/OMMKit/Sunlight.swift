import Foundation

/// What kind of light a stretch of time outside was. Bright light reaching the
/// eyes is what counts for the body clock, so time in the shade or behind glass
/// counts for less. The credits are rough rules of thumb, not measurements.
public enum SunlightKind: String, Codable, CaseIterable, Sendable {
    case openSky
    case shade
    case behindGlass

    /// The share of the minutes that count toward the goal.
    public var credit: Double {
        switch self {
        case .openSky: return 1
        case .shade: return 0.5
        case .behindGlass: return 0.25
        }
    }

    public var title: String {
        switch self {
        case .openSky: return "Open sky"
        case .shade: return "Shade"
        case .behindGlass: return "Behind glass"
        }
    }

    public var detail: String {
        switch self {
        case .openSky: return "Outside under the sky, sunny or cloudy. Counts in full."
        case .shade: return "Under trees, a porch or an umbrella. Counts about half."
        case .behindGlass: return "In a car or by a window. Counts about a quarter."
        }
    }
}

/// One stretch of time outside.
public struct SunlightEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Date
    public var minutes: Int
    public var kind: SunlightKind

    public init(id: UUID = UUID(), start: Date, minutes: Int, kind: SunlightKind) {
        self.id = id
        self.start = start
        self.minutes = minutes
        self.kind = kind
    }

    /// The minutes that count toward the goal, rounded to the nearest minute.
    public var creditedMinutes: Int {
        Int((Double(minutes) * kind.credit).rounded())
    }
}

/// One day's credited minutes, for the 7-day row.
public struct SunlightDay: Equatable, Identifiable, Sendable {
    public let day: Date
    public let minutes: Int
    public var id: Date { day }
}

/// A time of day, for reminders.
public struct TimeOfDay: Codable, Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public func date(on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

/// The daily sunlight goal, what's been logged, a running "I'm outside" timer
/// and the reminder times. Saved apart from the program so Reset Program keeps it.
public struct SunlightLog: Codable, Equatable, Sendable {
    public static let defaultGoal = 30
    public static let goalRange = 5...120
    public static let goalStep = 5
    /// Longest single entry, so a timer left running overnight can't count.
    public static let maxEntryMinutes = 240
    /// Entries older than this are dropped when saving.
    public static let keepDays = 60

    public var goalMinutes: Int
    public var entries: [SunlightEntry]
    /// When "I'm outside" was pressed, while the timer runs.
    public var outsideSince: Date?
    public var remindersOn: Bool
    public var morning: TimeOfDay
    public var midday: TimeOfDay
    public var lastCall: TimeOfDay

    public init(goalMinutes: Int = SunlightLog.defaultGoal, entries: [SunlightEntry] = [],
                outsideSince: Date? = nil, remindersOn: Bool = false,
                morning: TimeOfDay = TimeOfDay(hour: 8, minute: 0),
                midday: TimeOfDay = TimeOfDay(hour: 12, minute: 30),
                lastCall: TimeOfDay = TimeOfDay(hour: 16, minute: 0)) {
        self.goalMinutes = goalMinutes
        self.entries = entries
        self.outsideSince = outsideSince
        self.remindersOn = remindersOn
        self.morning = morning
        self.midday = midday
        self.lastCall = lastCall
    }

    // Decodes saves that lack newer fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = SunlightLog()
        goalMinutes = try c.decodeIfPresent(Int.self, forKey: .goalMinutes) ?? base.goalMinutes
        entries = try c.decodeIfPresent([SunlightEntry].self, forKey: .entries) ?? []
        outsideSince = try c.decodeIfPresent(Date.self, forKey: .outsideSince)
        remindersOn = try c.decodeIfPresent(Bool.self, forKey: .remindersOn) ?? base.remindersOn
        morning = try c.decodeIfPresent(TimeOfDay.self, forKey: .morning) ?? base.morning
        midday = try c.decodeIfPresent(TimeOfDay.self, forKey: .midday) ?? base.midday
        lastCall = try c.decodeIfPresent(TimeOfDay.self, forKey: .lastCall) ?? base.lastCall
    }

    public var isOutside: Bool { outsideSince != nil }

    /// Whole minutes since "I'm outside", capped at `maxEntryMinutes`.
    public func elapsedMinutes(now: Date) -> Int {
        guard let since = outsideSince else { return 0 }
        return min(Self.maxEntryMinutes, max(0, Int(now.timeIntervalSince(since) / 60)))
    }

    public func entries(on day: Date, calendar: Calendar = .current) -> [SunlightEntry] {
        entries.filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// Credited minutes logged on the day `day` falls on.
    public func minutes(on day: Date, calendar: Calendar = .current) -> Int {
        entries(on: day, calendar: calendar).reduce(0) { $0 + $1.creditedMinutes }
    }

    /// Today's credited minutes plus a running timer, counted as open sky
    /// until the kind is picked.
    public func minutesToday(now: Date, calendar: Calendar = .current) -> Int {
        var total = minutes(on: now, calendar: calendar)
        if let since = outsideSince, calendar.isDate(since, inSameDayAs: now) {
            total += elapsedMinutes(now: now)
        }
        return total
    }

    /// How far through the goal a day is, 0 to 1.
    public func fraction(minutes: Int) -> Double {
        guard goalMinutes > 0 else { return 1 }
        return min(1, Double(minutes) / Double(goalMinutes))
    }

    /// The last `count` days, oldest first, ending today: the day and its credited minutes.
    public func recentDays(_ count: Int = 7, now: Date, calendar: Calendar = .current) -> [SunlightDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let logged = back == 0 ? minutesToday(now: now, calendar: calendar) : minutes(on: day, calendar: calendar)
            return SunlightDay(day: day, minutes: logged)
        }
    }

    /// Days in a row the goal was met, ending today, or yesterday when today isn't met yet.
    public func streak(now: Date, calendar: Calendar = .current) -> Int {
        func logged(_ day: Date) -> Int {
            calendar.isDate(day, inSameDayAs: now) ? minutesToday(now: now, calendar: calendar)
                                                   : minutes(on: day, calendar: calendar)
        }
        var day = calendar.startOfDay(for: now)
        if logged(day) < goalMinutes {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while count <= Self.keepDays, logged(day) >= goalMinutes {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: Changes

    public mutating func startOutside(at date: Date) {
        if outsideSince == nil { outsideSince = date }
    }

    /// Stops the timer and logs it. Returns nil (and logs nothing) under a minute.
    @discardableResult
    public mutating func stopOutside(at date: Date, kind: SunlightKind, minutes: Int? = nil) -> SunlightEntry? {
        guard let since = outsideSince else { return nil }
        outsideSince = nil
        let length = min(Self.maxEntryMinutes, minutes ?? elapsedMinutes(now: date))
        guard length >= 1 else { return nil }
        let entry = SunlightEntry(start: since, minutes: length, kind: kind)
        entries.append(entry)
        return entry
    }

    public mutating func cancelOutside() {
        outsideSince = nil
    }

    /// Logs time outside after the fact.
    public mutating func add(minutes: Int, kind: SunlightKind, endingAt end: Date) {
        let length = min(Self.maxEntryMinutes, max(0, minutes))
        guard length >= 1 else { return }
        entries.append(SunlightEntry(start: end.addingTimeInterval(Double(-length) * 60), minutes: length, kind: kind))
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func setGoal(_ minutes: Int) {
        goalMinutes = min(Self.goalRange.upperBound, max(Self.goalRange.lowerBound, minutes))
    }

    /// Drops entries older than `keepDays`.
    public mutating func prune(now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: calendar.startOfDay(for: now)) else { return }
        entries.removeAll { $0.start < cutoff }
    }
}

/// A reminder to go outside, ready to be scheduled as a local notification.
public struct SunlightReminder: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case morning, midday, lastCall
    }

    public let id: String
    public let kind: Kind
    public let date: Date
    public let title: String
    public let body: String
}

public enum SunlightReminders {
    /// How many days ahead to schedule, so reminders keep coming on days the app isn't opened.
    public static let daysAhead = 7

    /// Reminders from `now` on, for today and the next days:
    /// - morning, every day the goal isn't met yet
    /// - midday, only while under half the goal
    /// - last call, while under the goal
    /// Today's are skipped while the timer is running. Future days have nothing
    /// logged yet, so all three are planned; they're re-planned each time time is logged.
    public static func plan(for log: SunlightLog, now: Date, calendar: Calendar = .current) -> [SunlightReminder] {
        guard log.remindersOn else { return [] }
        let today = calendar.startOfDay(for: now)
        var reminders: [SunlightReminder] = []
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let isToday = offset == 0
            if isToday && log.isOutside { continue }
            let logged = isToday ? log.minutes(on: now, calendar: calendar) : 0
            let goal = log.goalMinutes
            let left = max(0, goal - logged)
            let dayKey = DayKey.string(for: day, calendar: calendar)
            func add(_ kind: SunlightReminder.Kind, _ time: TimeOfDay, _ title: String, _ body: String) {
                guard let date = time.date(on: day, calendar: calendar), date > now else { return }
                reminders.append(SunlightReminder(id: "sunlight-\(kind.rawValue)-\(dayKey)", kind: kind,
                                                  date: date, title: title, body: body))
            }
            guard logged < goal else { continue }
            add(.morning, log.morning, "Morning light",
                "Step outside for a few minutes. Morning daylight helps set your body clock. Goal today: \(goal) min.")
            if logged * 2 < goal {
                add(.midday, log.midday, "Time for some daylight",
                    "You're under half your sunlight goal. \(left) min to go.")
            }
            add(.lastCall, log.lastCall, "Last call for daylight",
                "\(left) min left on today's sunlight goal before it gets dark.")
        }
        return reminders.sorted { $0.date < $1.date }
    }
}
