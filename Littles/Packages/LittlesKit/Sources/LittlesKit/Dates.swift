import Foundation

/// Days are `yyyy-MM-dd` strings ("day keys") in the model, never `Date`, so a
/// birthday or a school day doesn't shift when the phone changes time zone.
/// Times of day are `Int` minutes after midnight.
public enum Dates {
    /// The Gregorian calendar in the phone's time zone. Tests pass their own.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    public static func key(_ date: Date, calendar: Calendar = Dates.calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }

    /// Midnight at the start of the day a key names, or nil for a bad key.
    public static func date(_ key: String, calendar: Calendar = Dates.calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    public static func addDays(_ key: String, _ days: Int, calendar: Calendar = Dates.calendar) -> String {
        guard let day = Dates.date(key, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: day) else { return key }
        return Dates.key(moved, calendar: calendar)
    }

    /// 1 is Sunday through 7 is Saturday, as `Calendar` counts them.
    public static func weekday(_ key: String, calendar: Calendar = Dates.calendar) -> Int {
        guard let day = Dates.date(key, calendar: calendar) else { return 1 }
        return calendar.component(.weekday, from: day)
    }

    /// Whole days from 2000-01-01, so "today's pick" changes once a day.
    public static func ordinal(_ key: String, calendar: Calendar = Dates.calendar) -> Int {
        guard let day = Dates.date(key, calendar: calendar), let start = Dates.date("2000-01-01", calendar: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: start, to: day).day ?? 0
    }

    public static func minutes(_ date: Date, calendar: Calendar = Dates.calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The moment `minutes` after midnight on the day a key names.
    public static func at(_ key: String, minutes: Int, calendar: Calendar = Dates.calendar) -> Date? {
        guard let day = date(key, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .minute, value: minutes, to: day)
    }

    /// "8:05 AM" style, from minutes after midnight.
    public static func clock(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        let hour = wrapped / 60
        let minute = wrapped % 60
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", twelve, minute, hour < 12 ? "AM" : "PM")
    }

    /// "1h 25m", "40m", "2h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds / 60))
        let hours = total / 60
        let minutes = total % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    /// The weekday names, Sunday first, matching `weekday`.
    public static let shortWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    public static let letterWeekdays = ["S", "M", "T", "W", "T", "F", "S"]
}

public enum Age {
    /// Whole months from the birthday to `date` (0 before the first month-day).
    public static func months(birthday: String, on date: Date, calendar: Calendar = Dates.calendar) -> Int {
        guard let born = Dates.date(birthday, calendar: calendar) else { return 0 }
        let start = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.month], from: born, to: start).month ?? 0)
    }

    public static func days(birthday: String, on date: Date, calendar: Calendar = Dates.calendar) -> Int {
        guard let born = Dates.date(birthday, calendar: calendar) else { return 0 }
        let start = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: born, to: start).day ?? 0)
    }

    /// "3 wk" under a month, "8 mo" under two years, then "3 yr 4 mo".
    public static func label(birthday: String, on date: Date, calendar: Calendar = Dates.calendar) -> String {
        guard Dates.date(birthday, calendar: calendar) != nil else { return "" }
        let months = Age.months(birthday: birthday, on: date, calendar: calendar)
        if months < 1 {
            let days = Age.days(birthday: birthday, on: date, calendar: calendar)
            return days < 7 ? "\(days) d" : "\(days / 7) wk"
        }
        if months < 24 { return "\(months) mo" }
        let years = months / 12
        let rest = months % 12
        return rest == 0 ? "\(years) yr" : "\(years) yr \(rest) mo"
    }

    /// "6 mo", "2 yr", "18 mo" for an age in months, used on activity and food labels.
    public static func short(months: Int) -> String {
        if months < 24 { return "\(months) mo" }
        if months % 12 == 0 { return "\(months / 12) yr" }
        if months % 12 == 6 { return "\(months / 12)½ yr" }
        return "\(months / 12) yr \(months % 12) mo"
    }
}
