import Foundation

/// A calendar date with no time or time zone, stored as "yyyy-MM-dd" like
/// the web app's day keys. Deadlines, events and per-day settings use it.
public struct CalendarDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses "yyyy-MM-dd".
    public init?(key: String) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { key }

    /// Local midnight at the start of this day.
    public func startDate(calendar: Calendar) -> Date {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        return calendar.startOfDay(for: noon)
    }

    /// The local time `minutes` after this day's midnight, by the wall clock.
    /// Values past 1440 roll into the next day.
    public func date(atMinute minutes: Double, calendar: Calendar) -> Date {
        let total = Int(minutes.rounded())
        let dayOffset = Int((Double(total) / 1440).rounded(.down))
        let within = total - dayOffset * 1440
        let base = adding(days: dayOffset, calendar: calendar).startDate(calendar: calendar)
        return calendar.date(bySettingHour: within / 60, minute: within % 60, second: 0, of: base) ?? base
    }

    public func adding(days: Int, calendar: Calendar) -> CalendarDay {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        let moved = calendar.date(byAdding: .day, value: days, to: noon) ?? noon
        return CalendarDay(moved, calendar: calendar)
    }

    /// Whole days from this day to `other`; negative when `other` is earlier.
    public func days(until other: CalendarDay, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: startDate(calendar: calendar), to: other.startDate(calendar: calendar)).day ?? 0
    }

    /// 0 = Sunday … 6 = Saturday, the web app's numbering.
    public func weekdayIndex(calendar: Calendar) -> Int {
        calendar.component(.weekday, from: startDate(calendar: calendar)) - 1
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CalendarDay: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let key = try container.decode(String.self)
        guard let day = CalendarDay(key: key) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad day key \(key)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

extension Calendar {
    /// Minutes since local midnight, with seconds as a fraction.
    public func minuteOfDay(_ date: Date) -> Double {
        let parts = dateComponents([.hour, .minute, .second], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
    }

    /// Monday 00:00 of the week containing `date`.
    public func mondayOfWeek(containing date: Date) -> Date {
        let start = startOfDay(for: date)
        let weekday = component(.weekday, from: start) // 1 = Sunday
        let back = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -back, to: start) ?? start
    }

    /// Days left in the Monday-to-Sunday week, counting today: 7 on Monday, 1 on Sunday.
    public func daysLeftInWeek(_ date: Date) -> Int {
        let weekday = component(.weekday, from: date)
        return 7 - (weekday + 5) % 7
    }

    /// Whole calendar days from `a` to `b`.
    public func daysBetween(_ a: Date, _ b: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: a), to: startOfDay(for: b)).day ?? 0
    }
}
