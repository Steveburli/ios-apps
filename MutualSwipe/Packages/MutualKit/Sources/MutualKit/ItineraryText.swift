import Foundation

/// Turns pasted text, or the words read from a web page, into a plan for
/// people to check: "Drinks at 4 pm, movie at 6, dinner at 8" becomes three
/// stops. Only the outline is kept (the title, the times and the places), so
/// a plan pasted from somewhere else ends up in Mutual's own words.
public enum ItineraryText {
    public struct Result: Equatable, Sendable {
        public var title: String
        public var plan: Itinerary
    }

    /// Words that name what you do at a stop, not where.
    static let activities: Set<String> = [
        "drinks", "drink", "cocktails", "cocktail", "a drink", "happy hour", "beer", "beers", "wine", "coffee", "dessert",
        "ice cream", "dinner", "lunch", "brunch", "breakfast", "snacks", "appetizers", "apps", "movie", "a movie", "the movie",
        "film", "show", "a show", "the show", "concert", "music", "live music", "jazz", "comedy", "bowling", "games",
        "walk", "a walk", "stroll", "nightcap", "a nightcap", "shopping", "museum", "pizza", "tacos", "karaoke",
        "trivia", "mini golf", "golf", "skating", "paddle boats", "picnic", "sunset", "late night", "late-night bite",
    ]

    public static func parse(_ text: String) -> Result {
        let entries = text.components(separatedBy: .newlines).compactMap { raw -> (text: String, bullet: Bool)? in
            let line = stripBullet(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !isLink(line) else { return nil }
            return (line, hasBullet(raw))
        }
        let anyTimes = entries.contains { !timeMatches(in: $0.text).isEmpty }
        let anyBullets = entries.contains { $0.bullet }

        var title = ""
        var stops: [Itinerary.Stop] = []
        for entry in entries {
            let line = entry.text
            let times = timeMatches(in: line)
            if !times.isEmpty {
                for segment in segments(of: line, times: times) {
                    stops.append(stop(from: segment.text, time: segment.time))
                }
                continue
            }
            if stops.isEmpty && title.isEmpty && line.count <= 90 && !entry.bullet {
                title = line.trimmingCharacters(in: CharacterSet(charactersIn: ":.!"))
                continue
            }
            if !anyTimes && line.count <= 90 && (anyBullets ? entry.bullet : entries.count <= Itinerary.maxStops + 1) {
                stops.append(stop(from: line, time: nil))
                continue
            }
            // Extra lines describe the stop before them: an address, or a short note.
            guard var last = stops.popLast() else { continue }
            if last.address.isEmpty && looksLikeAddress(line) {
                last.address = line
            } else if last.note.isEmpty && line.count <= 160 {
                last.note = line
            }
            stops.append(last)
        }

        if title.isEmpty { title = madeUpTitle(stops) }
        let plan = Itinerary(stops: stops, area: area(in: title)).cleaned()
        return Result(title: String(title.prefix(120)), plan: plan)
    }

    // MARK: Lines

    private static let bulletPattern = "^\\s*(?:[-*•▪◦·]|\\d+[.)]|stop\\s*\\d+[:.)]?)\\s+"

    static func hasBullet(_ line: String) -> Bool {
        line.range(of: bulletPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func stripBullet(_ line: String) -> String {
        var line = line
        if let range = line.range(of: bulletPattern, options: [.regularExpression, .caseInsensitive]) {
            line.removeSubrange(range)
        }
        return line
    }

    static func isLink(_ line: String) -> Bool {
        line.range(of: "^https?://\\S+$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func looksLikeAddress(_ line: String) -> Bool {
        line.range(of: "^\\d+\\s+\\S+", options: .regularExpression) != nil && line.count <= 120
    }

    // MARK: Times

    struct TimeMatch {
        let range: Range<String.Index>
        let minutes: Int
    }

    /// Every time of day in a line: "4 pm", "6:30pm", "noon", "at 6" (read as evening).
    static func timeMatches(in line: String) -> [TimeMatch] {
        let morning = line.range(of: "\\b(morning|brunch|breakfast|sunrise)\\b", options: [.regularExpression, .caseInsensitive]) != nil
        var found: [TimeMatch] = []
        func add(_ pattern: String, _ make: (NSTextCheckingResult, String) -> Int?) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let range = Range(match.range(at: 1), in: line),
                      !found.contains(where: { $0.range.overlaps(range) }),
                      let minutes = make(match, line) else { continue }
                found.append(TimeMatch(range: range, minutes: minutes))
            }
        }
        func int(_ match: NSTextCheckingResult, _ i: Int, _ line: String) -> Int? {
            Range(match.range(at: i), in: line).flatMap { Int(line[$0]) }
        }
        func guess(_ hour: Int, _ minute: Int) -> Int? {
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { return 12 * 60 + minute }
            return (morning ? hour : hour + 12) * 60 + minute
        }
        // 4 pm, 4:30 p.m.
        add("(?<![\\d:])((\\d{1,2})(?::([0-5]\\d))?\\s*([ap])\\.?\\s?m\\b\\.?)") { match, line in
            guard let hour = int(match, 2, line), (1...12).contains(hour) else { return nil }
            let minute = int(match, 3, line) ?? 0
            let pm = Range(match.range(at: 4), in: line).map { line[$0].lowercased() == "p" } ?? true
            return ((hour % 12) + (pm ? 12 : 0)) * 60 + minute
        }
        add("\\b(noon)\\b") { _, _ in 12 * 60 }
        add("\\b(midnight)\\b") { _, _ in 0 }
        // 18:30 or 6:30
        add("(?<![\\d:])((\\d{1,2}):([0-5]\\d))(?![\\d:])") { match, line in
            guard let hour = int(match, 2, line), let minute = int(match, 3, line) else { return nil }
            if hour >= 13 && hour <= 23 { return hour * 60 + minute }
            return guess(hour, minute)
        }
        // "at 6", "by 8"
        add("\\b(?:at|by|around|@)\\s+((\\d{1,2}))(?![\\d:])(?!\\s*(?:st|nd|rd|th|street|ave|avenue|road|rd\\.?)\\b)") { match, line in
            guard let hour = int(match, 2, line) else { return nil }
            return guess(hour, 0)
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    struct Segment {
        let text: String
        let time: Int
    }

    /// Splits a line with several times into one piece per time.
    static func segments(of line: String, times: [TimeMatch]) -> [Segment] {
        guard times.count > 1 else {
            var text = line
            text.removeSubrange(times[0].range)
            return [Segment(text: text, time: times[0].minutes)]
        }
        let separators = ["→", "->", ";", ",", " and then ", " then ", " followed by ", " | ", "•"]
        var pieces = [line]
        for separator in separators {
            pieces = pieces.flatMap { piece in
                piece.components(separatedBy: separator)
            }
        }
        var result: [Segment] = []
        var waiting = ""
        for piece in pieces {
            let matches = timeMatches(in: piece)
            if let first = matches.first {
                var text = piece
                text.removeSubrange(first.range)
                result.append(Segment(text: waiting + " " + text, time: first.minutes))
                waiting = ""
            } else if let last = result.popLast() {
                // No time of its own: it belongs to the stop before.
                result.append(Segment(text: last.text + ", " + piece, time: last.time))
            } else {
                waiting += " " + piece
            }
        }
        return result
    }

    // MARK: Stops

    private static let edgeWords = "(?:at|and|then|around|by|from|starting|start|@|until)"

    static func tidy(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let junk = CharacterSet(charactersIn: " -–—:@,.·;|>()")
        for _ in 0..<3 {
            text = text.trimmingCharacters(in: junk)
            if let range = text.range(of: "^\(edgeWords)\\b\\s*", options: [.regularExpression, .caseInsensitive]) {
                text.removeSubrange(range)
            }
            if let range = text.range(of: "\\s*\\b\(edgeWords)$", options: [.regularExpression, .caseInsensitive]) {
                text.removeSubrange(range)
            }
        }
        return text.trimmingCharacters(in: junk)
    }

    static func isActivity(_ text: String) -> Bool {
        activities.contains(text.lowercased().trimmingCharacters(in: .whitespaces))
    }

    static func activityLabel(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: "^(a|an|the|grab|get|catch|see)\\s+", options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func stop(from raw: String, time: Int?) -> Itinerary.Stop {
        let text = tidy(raw)
        var stop = Itinerary.Stop(time: time.map { Itinerary.format(minutes: $0) } ?? "")
        func split(_ separator: String, options: String.CompareOptions = []) -> (String, String)? {
            guard let range = text.range(of: separator, options: options) else { return nil }
            let before = tidy(String(text[..<range.lowerBound]))
            let after = tidy(String(text[range.upperBound...]))
            return before.isEmpty || after.isEmpty ? nil : (before, after)
        }
        if let pair = split(" at ", options: .caseInsensitive) ?? split(" @ ") ?? split(": ") {
            stop.what = activityLabel(pair.0)
            stop.place = pair.1
        } else if let pair = split(" – ") ?? split(" — ") ?? split(" - ") {
            let (first, second) = pair
            if isActivity(first) {
                stop.what = activityLabel(first)
                stop.place = second
            } else {
                stop.place = first
                if isActivity(second) { stop.what = activityLabel(second) } else { stop.note = second }
            }
        } else if isActivity(text) {
            stop.what = activityLabel(text)
        } else {
            stop.place = text
        }
        // "Thunderbird, 1127 Shelby St" keeps the street as the address.
        if let comma = stop.place.range(of: ", ") {
            let rest = String(stop.place[comma.upperBound...])
            if looksLikeAddress(rest) {
                stop.address = rest
                stop.place = String(stop.place[..<comma.lowerBound])
            }
        }
        return stop
    }

    // MARK: Titles

    /// "Broad Ripple" from "Dinner and a movie in Broad Ripple".
    public static func area(in title: String) -> String {
        let pattern = "\\b(?:in|around|near)\\s+((?:[A-Z][\\w'.&-]*)(?:\\s+(?:[A-Z][\\w'.&-]*|of|the))*)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: title, range: NSRange(title.startIndex..., in: title)).last,
              let range = Range(match.range(at: 1), in: title) else { return "" }
        return String(title[range]).trimmingCharacters(in: CharacterSet(charactersIn: " .,!"))
    }

    /// "Drinks, movie and dinner" when nothing named the plan.
    static func madeUpTitle(_ stops: [Itinerary.Stop]) -> String {
        var whats: [String] = []
        for stop in stops where !stop.what.isEmpty && !whats.contains(stop.what.lowercased()) {
            whats.append(stop.what.lowercased())
        }
        guard !whats.isEmpty else { return stops.isEmpty ? "" : "Night out" }
        let joined = whats.count == 1 ? whats[0]
            : whats.dropLast().joined(separator: ", ") + " and " + whats[whats.count - 1]
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}
