import Foundation

/// What goes on the calendar once the group agrees: only Super matches and
/// Matches, each at the card's own time or a placeholder time to change.
public enum CalendarPlan {
    /// How long an event lasts when the card doesn't say.
    public static let length: TimeInterval = 2 * 3600

    /// The cards everyone agreed on, Super matches first. Empty until at
    /// least two people have voted, since one person can't agree with a group.
    public static func matches(in state: DeckState) -> [Card] {
        guard state.participants.count >= 2 else { return [] }
        return state.cards(.perfect) + state.cards(.match)
    }

    /// The card's own time, or next Friday at 7 PM.
    public static func start(for card: Card, now: Date = Date(), calendar: Calendar = .current) -> Date {
        card.startsAt ?? placeholderStart(after: now, calendar: calendar)
    }

    /// Next Friday at 7 PM, for cards with no time of their own.
    public static func placeholderStart(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: 19, minute: 0, weekday: 6), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
    }

    /// The event's notes: the quick facts, then the details.
    public static func notes(for card: Card) -> String {
        [card.subtitle, card.details].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// A one-event calendar file (.ics) anyone can open to add the card to
    /// their own calendar, Google and Outlook included.
    public static func ics(for card: Card, start: Date, now: Date = Date()) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Mutual//Mutual Swipe//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(card.id)@mutual",
            "DTSTAMP:\(stamp(now))",
            "DTSTART:\(stamp(start))",
            "DTEND:\(stamp(start.addingTimeInterval(length)))",
            "SUMMARY:\(escape(card.title))",
        ]
        let notes = notes(for: card)
        if !notes.isEmpty { lines.append("DESCRIPTION:\(escape(notes))") }
        if !card.link.isEmpty { lines.append("URL:\(card.link)") }
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// A file name for the invite, made from the card's title.
    public static func fileName(for card: Card) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        let cleaned = String(card.title.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Event" : String(cleaned.prefix(60))) + ".ics"
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Lines longer than 75 bytes continue on the next line after a space.
    static func fold(_ line: String) -> String {
        var parts: [String] = []
        var current = ""
        var bytes = 0
        for character in line {
            let size = String(character).utf8.count
            let limit = parts.isEmpty ? 75 : 74
            if bytes + size > limit {
                parts.append(current)
                current = ""
                bytes = 0
            }
            current.append(character)
            bytes += size
        }
        parts.append(current)
        return parts.joined(separator: "\r\n ")
    }
}
