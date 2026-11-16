import Foundation

/// A meeting from a locked calendar (the Alignops work calendar to start).
/// It keeps its exact start and end: nothing moves it, and a task dropped on
/// top of it goes to the next open gap instead.
public struct Meeting: Codable, Identifiable, Equatable, Sendable {
    /// The calendar event's ID plus its start, so each repeat is its own meeting.
    public var id: String
    public var title: String
    public var day: CalendarDay
    /// Minutes after midnight. `end` can run past 1440 into the night.
    public var start: Int
    public var end: Int
    /// The calendar's name, such as "Alignops".
    public var calendar: String

    public init(id: String, title: String, day: CalendarDay, start: Int, end: Int, calendar: String) {
        self.id = id
        self.title = title
        self.day = day
        self.start = start
        self.end = max(start + 1, end)
        self.calendar = calendar
    }

    /// A meeting from a calendar event, on the day it starts. One that runs
    /// past midnight ends after 1440.
    public static func from(eventID: String, title: String, start: Date, end: Date, calendarName: String,
                            calendar: Calendar) -> Meeting {
        let day = CalendarDay(start, calendar: calendar)
        let midnight = day.startDate(calendar: calendar)
        let startMinute = Int((start.timeIntervalSince(midnight) / 60).rounded())
        let endMinute = Int((end.timeIntervalSince(midnight) / 60).rounded())
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Meeting(id: "\(eventID)@\(Int(start.timeIntervalSince1970))", title: trimmed.isEmpty ? "Meeting" : trimmed,
                       day: day, start: startMinute, end: endMinute, calendar: calendarName)
    }

    public var span: TimeSpan {
        TimeSpan(start: Double(start), end: Double(end))
    }

    private enum CodingKeys: String, CodingKey { case id, title, day, start, end, calendar }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  day: try c.decode(CalendarDay.self, forKey: .day),
                  start: try c.decodeIfPresent(Int.self, forKey: .start) ?? 9 * 60,
                  end: try c.decodeIfPresent(Int.self, forKey: .end) ?? 10 * 60,
                  calendar: try c.decodeIfPresent(String.self, forKey: .calendar) ?? "")
    }
}

/// Which calendars bring in locked meetings.
public struct MeetingSettings: Codable, Equatable, Sendable {
    /// Meetings come in from the locked calendars.
    public var on = false
    /// The calendars you picked, by calendar ID. Nil means the default: every
    /// calendar whose name has "Alignops" in it.
    public var calendarIDs: [String]?

    public init() {}

    /// Calendars whose name holds this lock by default.
    public static let defaultName = "alignops"

    /// Whether a calendar's meetings are locked.
    public func locks(calendarID: String, name: String) -> Bool {
        if let calendarIDs { return calendarIDs.contains(calendarID) }
        return name.lowercased().contains(Self.defaultName)
    }

    private enum CodingKeys: String, CodingKey { case on, calendarIDs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        calendarIDs = try c.decodeIfPresent([String].self, forKey: .calendarIDs)
    }
}

extension PlannerState {
    /// Replaces the saved meetings with what the calendars hold now.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func syncMeetings(_ fresh: [Meeting]) -> Bool {
        let sorted = fresh.stableSorted { ($0.day, $0.start) < ($1.day, $1.start) }
        guard sorted != meetings else { return false }
        meetings = sorted
        return true
    }

    /// The locked meetings on `day`, in time order.
    public func meetings(on day: CalendarDay) -> [Meeting] {
        meetingSettings.on ? meetings.filter { $0.day == day } : []
    }
}
