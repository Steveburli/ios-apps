import Foundation

/// A kind of weekly routine.
public enum RoutineKind: String, Codable, CaseIterable, Identifiable {
    case school, dropoff, pickup, lesson, nap, meal, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .school: return "Preschool"
        case .dropoff: return "Drop-off"
        case .pickup: return "Pickup"
        case .lesson: return "Class or lesson"
        case .nap: return "Nap"
        case .meal: return "Meal"
        case .other: return "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .school: return "🏫"
        case .dropoff: return "🚗"
        case .pickup: return "🎒"
        case .lesson: return "🤸"
        case .nap: return "😴"
        case .meal: return "🍽️"
        case .other: return "📌"
        }
    }

    /// School items that a "No school" day cancels.
    public var isSchool: Bool {
        self == .school || self == .dropoff || self == .pickup
    }
}

/// Something that happens on the same weekdays every week: preschool hours,
/// drop-off and pickup, swim class, nap.
public struct RoutineItem: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    /// Empty means every kid.
    public var kidIDs: [String]
    /// 1 is Sunday through 7 is Saturday.
    public var weekdays: [Int]
    public var start: Int
    public var end: Int?
    public var kind: RoutineKind
    public var place: String
    public var note: String
    /// Minutes before `start` for a reminder; nil for none.
    public var remind: Int?
    /// The first day it applies, `yyyy-MM-dd`; empty for always.
    public var from: String
    /// The last day it applies (the end of the school year); empty for always.
    public var until: String

    public init(id: String = UUID().uuidString, title: String, kidIDs: [String] = [], weekdays: [Int], start: Int,
                end: Int? = nil, kind: RoutineKind, place: String = "", note: String = "", remind: Int? = nil,
                from: String = "", until: String = "") {
        self.id = id
        self.title = title
        self.kidIDs = kidIDs
        self.weekdays = weekdays
        self.start = start
        self.end = end
        self.kind = kind
        self.place = place
        self.note = note
        self.remind = remind
        self.from = from
        self.until = until
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kidIDs = try c.decodeIfPresent([String].self, forKey: .kidIDs) ?? []
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        start = try c.decodeIfPresent(Int.self, forKey: .start) ?? 0
        end = try c.decodeIfPresent(Int.self, forKey: .end)
        kind = (try? c.decodeIfPresent(RoutineKind.self, forKey: .kind)) ?? .other
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        remind = try c.decodeIfPresent(Int.self, forKey: .remind)
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        until = try c.decodeIfPresent(String.self, forKey: .until) ?? ""
    }

    public func happens(on day: String, calendar: Calendar = Dates.calendar) -> Bool {
        if !from.isEmpty && day < from { return false }
        if !until.isEmpty && day > until { return false }
        return weekdays.contains(Dates.weekday(day, calendar: calendar))
    }

    /// "Mon, Wed, Fri" or "Weekdays".
    public var daysLabel: String {
        let sorted = Set(weekdays).sorted()
        if sorted == [2, 3, 4, 5, 6] { return "Weekdays" }
        if sorted == [1, 2, 3, 4, 5, 6, 7] { return "Every day" }
        if sorted == [1, 7] { return "Weekends" }
        return sorted.map { Dates.shortWeekdays[max(0, min(6, $0 - 1))] }.joined(separator: ", ")
    }
}

public enum EventKind: String, Codable, CaseIterable, Identifiable {
    case noSchool, special, earlyPickup, fieldTrip, party, doctor, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .noSchool: return "No school"
        case .special: return "Special day"
        case .earlyPickup: return "Early pickup"
        case .fieldTrip: return "Field trip"
        case .party: return "Party"
        case .doctor: return "Doctor"
        case .other: return "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .noSchool: return "🏠"
        case .special: return "🎉"
        case .earlyPickup: return "⏰"
        case .fieldTrip: return "🚌"
        case .party: return "🎂"
        case .doctor: return "🩺"
        case .other: return "📅"
        }
    }
}

/// Something on one day: pajama day, a field trip, no school, a checkup.
public struct OneOffEvent: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var kidIDs: [String]
    public var day: String
    public var start: Int?
    public var end: Int?
    public var kind: EventKind
    public var note: String
    /// Something to bring or wear ("Wear pajamas", "Bring $5").
    public var bring: String

    public init(id: String = UUID().uuidString, title: String, kidIDs: [String] = [], day: String, start: Int? = nil,
                end: Int? = nil, kind: EventKind, note: String = "", bring: String = "") {
        self.id = id
        self.title = title
        self.kidIDs = kidIDs
        self.day = day
        self.start = start
        self.end = end
        self.kind = kind
        self.note = note
        self.bring = bring
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kidIDs = try c.decodeIfPresent([String].self, forKey: .kidIDs) ?? []
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        start = try c.decodeIfPresent(Int.self, forKey: .start)
        end = try c.decodeIfPresent(Int.self, forKey: .end)
        kind = (try? c.decodeIfPresent(EventKind.self, forKey: .kind)) ?? .other
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        bring = try c.decodeIfPresent(String.self, forKey: .bring) ?? ""
    }
}

/// Something to send with a kid: nap blanket on Mondays, library book on Thursdays.
public struct PackItem: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var kidID: String
    /// Empty means every day that kid has school.
    public var weekdays: [Int]

    public init(id: String = UUID().uuidString, title: String, kidID: String, weekdays: [Int] = []) {
        self.id = id
        self.title = title
        self.kidID = kidID
        self.weekdays = weekdays
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kidID = try c.decodeIfPresent(String.self, forKey: .kidID) ?? ""
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
    }
}

/// One row on a day's agenda.
public struct AgendaEntry: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var emoji: String
    public var kidIDs: [String]
    public var start: Int?
    public var end: Int?
    public var place: String
    public var note: String
    /// A routine called off by a "No school" day; shown struck through.
    public var cancelled: Bool
    public var isEvent: Bool
}

/// One pack-list line for a day.
public struct PackLine: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var kidID: String?
    public var packed: Bool
}

public enum Agenda {
    /// Does an item for these kids include this kid? An empty list means everyone.
    static func includes(_ kidIDs: [String], _ kidID: String) -> Bool {
        kidIDs.isEmpty || kidIDs.contains(kidID)
    }

    /// Does a "No school" event cancel this routine? Only when it covers every kid the routine is for.
    static func cancels(_ event: OneOffEvent, _ routine: RoutineItem, allKids: [String]) -> Bool {
        guard event.kind == .noSchool, routine.kind.isSchool else { return false }
        if event.kidIDs.isEmpty { return true }
        let covered = routine.kidIDs.isEmpty ? allKids : routine.kidIDs
        return covered.allSatisfy { event.kidIDs.contains($0) }
    }

    /// The day's routines and events in time order (all-day events first).
    /// With `kidID`, only that kid's.
    public static func entries(on day: String, state: FamilyState, kidID: String? = nil,
                               calendar: Calendar = Dates.calendar) -> [AgendaEntry] {
        let allKids = state.kids.map { $0.id }
        let events = state.events.filter { $0.day == day && (kidID == nil || includes($0.kidIDs, kidID!)) }
        var result: [AgendaEntry] = []
        for routine in state.routines where routine.happens(on: day, calendar: calendar) {
            if let kidID, !includes(routine.kidIDs, kidID) { continue }
            let cancelled = events.contains { cancels($0, routine, allKids: allKids) }
            result.append(AgendaEntry(id: routine.id, title: routine.title, emoji: routine.kind.emoji, kidIDs: routine.kidIDs,
                                      start: routine.start, end: routine.end, place: routine.place, note: routine.note,
                                      cancelled: cancelled, isEvent: false))
        }
        for event in events {
            var note = event.note
            if !event.bring.isEmpty { note = note.isEmpty ? "Bring: \(event.bring)" : "\(note) · Bring: \(event.bring)" }
            result.append(AgendaEntry(id: event.id, title: event.title, emoji: event.kind.emoji, kidIDs: event.kidIDs,
                                      start: event.start, end: event.end, place: "", note: note,
                                      cancelled: false, isEvent: true))
        }
        return result.sorted { lhs, rhs in
            switch (lhs.start, rhs.start) {
            case (nil, nil): return lhs.title < rhs.title
            case (nil, _): return true
            case (_, nil): return false
            case let (l?, r?): return l != r ? l < r : lhs.title < rhs.title
            }
        }
    }

    /// Whether a kid has school (not cancelled) on a day.
    public static func hasSchool(_ kidID: String, on day: String, state: FamilyState,
                                 calendar: Calendar = Dates.calendar) -> Bool {
        entries(on: day, state: state, kidID: kidID, calendar: calendar)
            .contains { entry in
                !entry.cancelled && !entry.isEvent
                    && state.routines.first(where: { $0.id == entry.id })?.kind == .school
            }
    }

    /// What to pack for the day: each pack item due that day, plus anything an
    /// event says to bring.
    public static func packList(on day: String, state: FamilyState, calendar: Calendar = Dates.calendar) -> [PackLine] {
        let weekday = Dates.weekday(day, calendar: calendar)
        var lines: [PackLine] = []
        for item in state.packItems {
            let due = item.weekdays.isEmpty
                ? hasSchool(item.kidID, on: day, state: state, calendar: calendar)
                : item.weekdays.contains(weekday) && hasSchool(item.kidID, on: day, state: state, calendar: calendar)
            if due {
                lines.append(PackLine(id: item.id, title: item.title, kidID: item.kidID,
                                      packed: state.packed.contains(packKey(day, item.id))))
            }
        }
        for event in state.events where event.day == day && !event.bring.isEmpty {
            let id = "event-" + event.id
            lines.append(PackLine(id: id, title: event.bring, kidID: event.kidIDs.count == 1 ? event.kidIDs[0] : nil,
                                  packed: state.packed.contains(packKey(day, id))))
        }
        return lines
    }

    public static func packKey(_ day: String, _ id: String) -> String {
        day + "|" + id
    }

    /// The next routine or timed event at or after `now`, within a week.
    public static func next(after now: Date, state: FamilyState, calendar: Calendar = Dates.calendar) -> (day: String, entry: AgendaEntry)? {
        let today = Dates.key(now, calendar: calendar)
        let minute = Dates.minutes(now, calendar: calendar)
        for offset in 0..<8 {
            let day = Dates.addDays(today, offset, calendar: calendar)
            let upcoming = entries(on: day, state: state, calendar: calendar)
                .filter { !$0.cancelled && $0.start != nil && (offset > 0 || $0.start! >= minute) }
            if let first = upcoming.first { return (day, first) }
        }
        return nil
    }

    /// Pack keys for days before `today`, which can be dropped from saved state.
    public static func stalePackKeys(_ keys: [String], today: String) -> [String] {
        keys.filter { key in
            guard let day = key.split(separator: "|").first else { return true }
            return String(day) < today
        }
    }
}
