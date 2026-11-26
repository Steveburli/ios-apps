import Foundation

/// Reads school calendars: an .ics file or link, or the text of a photo of a
/// paper calendar (one date and title per line).
public enum CalendarImport {
    public struct Found: Equatable, Identifiable {
        public var title: String
        public var day: String
        public var start: Int?
        public var kind: EventKind
        public var id: String { day + "|" + title }
    }

    /// Guesses the event kind from its title.
    public static func kind(for title: String) -> EventKind {
        let text = title.lowercased()
        let words: [(EventKind, [String])] = [
            (.noSchool, ["no school", "closed", "holiday", "break", "day off", "no class", "teacher work", "in-service",
                         "inservice", "professional development", "conferences"]),
            (.earlyPickup, ["early dismissal", "early release", "half day", "noon dismissal"]),
            (.fieldTrip, ["field trip"]),
            (.party, ["party", "celebration", "birthday"]),
            (.doctor, ["doctor", "dentist", "checkup", "well visit"]),
        ]
        for (kind, keys) in words where keys.contains(where: { text.contains($0) }) { return kind }
        return .special
    }

    // MARK: iCalendar

    public static func ics(_ text: String, calendar: Calendar = Dates.calendar) -> [Found] {
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
        var found: [Found] = []
        var inEvent = false
        var summary = ""
        var start: (day: String, minute: Int?)?
        var end: (day: String, minute: Int?)?
        for raw in unfolded.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "BEGIN:VEVENT" {
                inEvent = true
                summary = ""
                start = nil
                end = nil
                continue
            }
            if line == "END:VEVENT" {
                inEvent = false
                guard let start, !summary.isEmpty else { continue }
                var lastDay = start.day
                if let end, start.minute == nil {
                    // All-day events end the day before DTEND.
                    lastDay = max(start.day, Dates.addDays(end.day, -1, calendar: calendar))
                }
                var day = start.day
                var count = 0
                while day <= lastDay && count < 21 {
                    found.append(Found(title: summary, day: day, start: day == start.day ? start.minute : nil, kind: kind(for: summary)))
                    day = Dates.addDays(day, 1, calendar: calendar)
                    count += 1
                }
                continue
            }
            guard inEvent, let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].split(separator: ";").first.map(String.init)?.uppercased() ?? ""
            let value = String(line[line.index(after: colon)...])
            switch key {
            case "SUMMARY":
                summary = value.replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
                    .replacingOccurrences(of: "\\n", with: " ").trimmingCharacters(in: .whitespaces)
            case "DTSTART":
                start = icsDate(value, calendar: calendar)
            case "DTEND":
                end = icsDate(value, calendar: calendar)
            default:
                break
            }
        }
        return found
    }

    /// "20261127" (all day), "20261127T083000" (local) or "20261127T133000Z" (UTC).
    static func icsDate(_ value: String, calendar: Calendar) -> (day: String, minute: Int?)? {
        let digits = value.filter { $0.isNumber }
        guard digits.count >= 8 else { return nil }
        let chars = Array(digits)
        func number(_ from: Int, _ length: Int) -> Int { Int(String(chars[from..<min(chars.count, from + length)])) ?? 0 }
        let year = number(0, 4), month = number(4, 2), day = number(6, 2)
        guard digits.count >= 12 else { return (String(format: "%04d-%02d-%02d", year, month, day), nil) }
        let hour = number(8, 2), minute = number(10, 2)
        if value.hasSuffix("Z") {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            guard let date = utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) else { return nil }
            return (Dates.key(date, calendar: calendar), Dates.minutes(date, calendar: calendar))
        }
        return (String(format: "%04d-%02d-%02d", year, month, day), hour * 60 + minute)
    }

    // MARK: Text from a photo

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Lines like "Nov 27 – No School", "12/5 Picture Day", "Dec 22-Jan 2 Winter Break".
    /// The year is the one that puts the date nearest today (up to 2 months back).
    public static func lines(_ lines: [String], today: String, calendar: Calendar = Dates.calendar) -> [Found] {
        let monthPattern = "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?"
        let named = try? NSRegularExpression(pattern:
            "\\b\(monthPattern)\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*[-–—]\\s*(?:\(monthPattern)\\s+)?(\\d{1,2})(?:st|nd|rd|th)?)?\\b",
            options: [.caseInsensitive])
        let numeric = try? NSRegularExpression(pattern:
            "\\b(\\d{1,2})/(\\d{1,2})(?:/\\d{2,4})?(?:\\s*[-–—]\\s*(\\d{1,2})/(\\d{1,2})(?:/\\d{2,4})?)?\\b", options: [])
        var found: [Found] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(line.startIndex..., in: line)
            var startMonth = 0, startDay = 0, endMonth = 0, endDay = 0
            var matchRange: Range<String.Index>?
            if let match = named?.firstMatch(in: line, range: range) {
                func group(_ index: Int) -> String? {
                    guard let r = Range(match.range(at: index), in: line) else { return nil }
                    return String(line[r]).lowercased()
                }
                startMonth = (months.firstIndex(of: String((group(1) ?? "").prefix(3))) ?? -1) + 1
                startDay = Int(group(2) ?? "") ?? 0
                endMonth = group(3).flatMap { months.firstIndex(of: String($0.prefix(3))) }.map { $0 + 1 } ?? startMonth
                endDay = Int(group(4) ?? "") ?? startDay
                matchRange = Range(match.range, in: line)
            } else if let match = numeric?.firstMatch(in: line, range: range) {
                func group(_ index: Int) -> Int? {
                    guard let r = Range(match.range(at: index), in: line) else { return nil }
                    return Int(line[r])
                }
                startMonth = group(1) ?? 0
                startDay = group(2) ?? 0
                endMonth = group(3) ?? startMonth
                endDay = group(4) ?? startDay
                matchRange = Range(match.range, in: line)
            }
            guard (1...12).contains(startMonth), (1...31).contains(startDay), let matchRange else { continue }
            var title = line
            title.removeSubrange(matchRange)
            title = cleanTitle(title)
            guard !title.isEmpty, let first = nearest(month: startMonth, day: startDay, today: today, calendar: calendar) else { continue }
            var last = first
            if (1...12).contains(endMonth), (1...31).contains(endDay),
               let end = nearest(month: endMonth, day: endDay, today: first, calendar: calendar, back: 0), end > first {
                last = end
            }
            var day = first
            var count = 0
            while day <= last && count < 21 {
                found.append(Found(title: title, day: day, start: nil, kind: kind(for: title)))
                day = Dates.addDays(day, 1, calendar: calendar)
                count += 1
            }
        }
        return found
    }

    static func cleanTitle(_ text: String) -> String {
        let trim = CharacterSet(charactersIn: " -–—:,.|•\t")
        var title = text.trimmingCharacters(in: trim)
        let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun"]
        for _ in 0..<2 {
            let lower = title.lowercased()
            if let word = weekdays.first(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") || lower.hasPrefix($0 + ".") }) {
                title = String(title.dropFirst(word.count))
            } else if let word = weekdays.first(where: { lower.hasSuffix("(" + $0 + ")") }) {
                title = String(title.dropLast(word.count + 2))
            } else if let word = weekdays.first(where: { lower.hasSuffix(" " + $0) }) {
                title = String(title.dropLast(word.count))
            }
            title = title.trimmingCharacters(in: trim)
        }
        return title
    }

    /// The date with this month and day closest after `today` minus `back` days.
    static func nearest(month: Int, day: Int, today: String, calendar: Calendar, back: Int = 60) -> String? {
        guard let year = Int(today.prefix(4)) else { return nil }
        let earliest = Dates.addDays(today, -back, calendar: calendar)
        for candidate in [year - 1, year, year + 1] {
            let key = String(format: "%04d-%02d-%02d", candidate, month, day)
            guard Dates.date(key, calendar: calendar) != nil else { continue }
            if key >= earliest { return key }
        }
        return nil
    }

    /// Turns what was found into events for these kids. Skips ones already on
    /// the schedule (same day and title).
    public static func events(_ found: [Found], kidIDs: [String], existing: [OneOffEvent], source: String) -> [OneOffEvent] {
        let have = Set(existing.map { $0.day + "|" + $0.title.lowercased() })
        var seen = Set<String>()
        return found.compactMap { item in
            let key = item.day + "|" + item.title.lowercased()
            guard !have.contains(key), !seen.contains(key) else { return nil }
            seen.insert(key)
            return OneOffEvent(title: item.title, kidIDs: kidIDs, day: item.day, start: item.start, kind: item.kind, source: source)
        }
    }
}

/// Reads a pasted daily report from preschool or daycare (Brightwheel,
/// Tadpoles, a teacher's email) into log entries to check before saving.
public enum DailyReport {
    public static func parse(_ text: String, kidID: String, day: String, calendar: Calendar = Dates.calendar) -> [LogEntry] {
        var entries: [LogEntry] = []
        var notes: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            let times = clockTimes(in: lower)
            let at = Dates.at(day, minutes: times.first ?? 12 * 60, calendar: calendar) ?? Date()
            func has(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }

            if has(["nap", "slept", "sleep"]) {
                let end = times.count > 1 ? Dates.at(day, minutes: times[1], calendar: calendar) : nil
                entries.append(LogEntry(kidID: kidID, kind: .sleep, start: at, end: end ?? at.addingTimeInterval(3600),
                                        note: times.count > 1 ? "" : "From school (time not given)"))
            } else if has(["diaper", " bm", "bm ", "wet", "dirty"]) && !has(["potty", "toilet"]) {
                let dirty = has(["bm", "dirty", "poop", "bowel"])
                let wet = has(["wet"])
                let kind: DiaperKind = dirty && wet ? .mixed : (dirty ? .dirty : (has(["dry"]) ? .dry : .wet))
                entries.append(LogEntry(kidID: kidID, kind: .diaper, start: at, diaper: kind))
            } else if has(["potty", "toilet", "bathroom"]) {
                let kind: PottyKind = has(["accident"]) ? .accident : (has(["poop", "bm"]) ? .poop : (has(["tried", "sat on"]) ? .tried : .pee))
                entries.append(LogEntry(kidID: kidID, kind: .potty, start: at, potty: kind))
            } else if has(["bottle", "formula", "breast milk"]) {
                entries.append(LogEntry(kidID: kidID, kind: .bottle, start: at, amountOz: ounces(in: lower),
                                        milk: has(["breast milk"]) ? .breastMilk : (has(["formula"]) ? .formula : nil)))
            } else if has(["breakfast", "lunch", "snack", "ate ", "meal", "dinner"]) {
                let bites = foods(in: lower).map { FoodBite(foodID: $0, liking: has(["all", "most", "loved", "seconds"]) ? .liked : (has(["none", "didn't", "did not", "refused"]) ? .refused : .liked)) }
                entries.append(LogEntry(kidID: kidID, kind: .solids, start: at, bites: bites, note: line))
            } else if has(["medicine", "tylenol", "motrin", "ibuprofen", "acetaminophen"]) {
                entries.append(LogEntry(kidID: kidID, kind: .meds, start: at, medicine: line))
            } else {
                notes.append(line)
            }
        }
        if !notes.isEmpty {
            let at = Dates.at(day, minutes: 15 * 60, calendar: calendar) ?? Date()
            entries.append(LogEntry(kidID: kidID, kind: .note, start: at, note: "From school: " + notes.joined(separator: " · ")))
        }
        return entries.sorted { $0.start < $1.start }
    }

    /// Clock times in a line, in minutes after midnight. Times without AM or PM
    /// before 7 are taken as afternoon (school hours).
    static func clockTimes(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: "\\b(\\d{1,2})(?::(\\d{2}))?\\s*(a\\.?m\\.?|p\\.?m\\.?)?(?![\\d])",
                                                   options: [.caseInsensitive]) else { return [] }
        var result: [Int] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func group(_ index: Int) -> String? {
                guard let r = Range(match.range(at: index), in: text) else { return nil }
                return String(text[r])
            }
            let minute = group(2).flatMap { Int($0) }
            let meridiem = group(3)?.lowercased()
            // A plain number ("4 oz") isn't a time.
            guard minute != nil || meridiem != nil, var hour = group(1).flatMap({ Int($0) }), hour <= 12 else { continue }
            if let meridiem {
                if meridiem.hasPrefix("p") && hour < 12 { hour += 12 }
                if meridiem.hasPrefix("a") && hour == 12 { hour = 0 }
            } else if hour < 7 {
                hour += 12
            }
            result.append(hour * 60 + (minute ?? 0))
        }
        return result
    }

    static func ounces(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s*(?:oz|ounces)", options: []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }

    /// Guide foods named in the text.
    static func foods(in text: String) -> [String] {
        FoodGuide.all.filter { food in
            let name = food.name.lowercased()
            let short = name.components(separatedBy: CharacterSet(charactersIn: " /(")).first ?? name
            let singular = short.hasSuffix("s") ? String(short.dropLast()) : short
            return text.contains(name) || (singular.count > 3 && text.contains(singular))
        }.map { $0.id }
    }
}
