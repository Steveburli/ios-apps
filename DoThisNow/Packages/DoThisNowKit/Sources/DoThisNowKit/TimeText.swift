import Foundation

public enum TimeText {
    /// "45m", "1h", "1h 30m".
    public static func duration(_ minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        if m < 60 { return "\(m)m" }
        let hours = m / 60, rest = m % 60
        return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h"
    }

    public static func duration(_ minutes: Int) -> String {
        duration(Double(minutes))
    }

    /// "a day", "5 days", "3 weeks", "4 months", "1.5 years".
    public static func ago(days: Double) -> String {
        if days < 1.5 { return "a day" }
        if days < 14 { return "\(Int(days.rounded())) days" }
        if days < 60 { return "\(Int((days / 7).rounded())) weeks" }
        if days < 365 { return "\(Int((days / 30).rounded())) months" }
        let years = (days / 365 * 10).rounded() / 10
        return years == years.rounded() ? "\(Int(years)) years" : "\(years) years"
    }
}

/// Locale-aware date and time strings, made once and reused.
public final class Formats {
    public let calendar: Calendar
    private let timeFormatter: DateFormatter
    private let hourFormatter: DateFormatter
    private let weekdayFormatter: DateFormatter
    private let monthDayFormatter: DateFormatter
    private let shortFormatter: DateFormatter

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
        func make(_ template: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = calendar.locale ?? .current
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        timeFormatter = make("jmm")
        hourFormatter = make("j")
        weekdayFormatter = make("EEEE")
        monthDayFormatter = make("MMMd")
        shortFormatter = make("EEEMMMd")
    }

    /// "6:30 PM"
    public func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    public func time(_ day: CalendarDay, _ minutes: Double) -> String {
        timeFormatter.string(from: day.date(atMinute: minutes, calendar: calendar))
    }

    /// "6:30 PM–7:00 PM"
    public func range(_ day: CalendarDay, _ from: Double, _ to: Double) -> String {
        "\(time(day, from))–\(time(day, to))"
    }

    /// "6 PM"
    public func hour(_ day: CalendarDay, _ minutes: Double) -> String {
        hourFormatter.string(from: day.date(atMinute: minutes, calendar: calendar))
    }

    /// "Friday"
    public func weekdayName(_ day: CalendarDay) -> String {
        weekdayFormatter.string(from: day.startDate(calendar: calendar))
    }

    /// "Oct 17"
    public func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    /// "Sat, Oct 17"
    public func shortDate(_ date: Date) -> String {
        shortFormatter.string(from: date)
    }

    public func shortDate(_ day: CalendarDay) -> String {
        shortFormatter.string(from: day.startDate(calendar: calendar))
    }

    /// "at 6:30 PM", "tomorrow at 9:00 AM", "Friday at 7:00 AM", "on Oct 30".
    public func when(_ date: Date, now: Date) -> String {
        let diff = calendar.daysBetween(now, date)
        let t = time(date)
        if diff == 0 { return "at \(t)" }
        if diff == 1 { return "tomorrow at \(t)" }
        if diff < 7 { return "\(weekdayFormatter.string(from: date)) at \(t)" }
        return "on \(monthDay(date))"
    }
}
