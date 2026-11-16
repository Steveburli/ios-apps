import XCTest
@testable import MutualKit

final class CalendarPlanTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func card(_ id: String, _ title: String, order: Double, at time: Date? = nil) -> Card {
        Card(id: id, groupID: "g", deckID: "d", draft: CardDraft(title: title, startsAt: time), order: order, createdAt: start)
    }

    private func pick(_ cardID: String, _ playerID: String, _ vote: Vote) -> Pick {
        Pick(groupID: "g", deckID: "d", cardID: cardID, playerID: playerID, vote: vote, updatedAt: start)
    }

    private let players = [
        Player(id: "a", groupID: "g", name: "A", color: 0, createdAt: Date(timeIntervalSince1970: 1)),
        Player(id: "b", groupID: "g", name: "B", color: 1, createdAt: Date(timeIntervalSince1970: 2)),
    ]

    func testOnlySuperMatchesAndMatches() {
        let cards = [card("m", "Match", order: 1), card("s", "Super", order: 2), card("x", "Split", order: 3),
                     card("d", "Debate", order: 4), card("p", "Pending", order: 5)]
        let picks = [
            pick("m", "a", .like), pick("m", "b", .love),
            pick("s", "a", .love), pick("s", "b", .love),
            pick("x", "a", .like), pick("x", "b", .nope),
            pick("d", "a", .love), pick("d", "b", .nope),
            pick("p", "a", .like),
        ]
        let state = DeckState(cards: cards, players: players, picks: picks, me: "a")
        XCTAssertEqual(CalendarPlan.matches(in: state).map(\.id), ["s", "m"])
    }

    func testNeedsTwoPeople() {
        let state = DeckState(cards: [card("c", "Solo", order: 1)], players: players, picks: [pick("c", "a", .love)], me: "a")
        XCTAssertTrue(CalendarPlan.matches(in: state).isEmpty)
    }

    func testCardTimeWinsOverPlaceholder() {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(CalendarPlan.start(for: card("c", "Show", order: 1, at: time), now: start), time)
    }

    func testPlaceholderIsNextFridayEvening() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        let placeholder = CalendarPlan.placeholderStart(after: start, calendar: calendar)
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: placeholder)
        XCTAssertEqual(parts.weekday, 6)
        XCTAssertEqual(parts.hour, 19)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertGreaterThan(placeholder, start)
    }

    func testCleanKeepsTime() {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(CardText.clean(CardDraft(title: " Show ", startsAt: time))?.startsAt, time)
    }

    func testICS() {
        var event = card("abc", "Jazz, wine; and a view", order: 1)
        event.subtitle = "$$ · late"
        event.details = "Line one\nLine two"
        event.link = "https://example.com"
        let ics = CalendarPlan.ics(for: event, start: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 60))
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("UID:abc@mutual\r\n"))
        XCTAssertTrue(ics.contains("DTSTART:19700101T000000Z\r\n"))
        XCTAssertTrue(ics.contains("DTEND:19700101T020000Z\r\n"))
        XCTAssertTrue(ics.contains("SUMMARY:Jazz\\, wine\\; and a view\r\n"))
        XCTAssertTrue(ics.contains("DESCRIPTION:$$ · late\\n\\nLine one\\nLine two\r\n"))
        XCTAssertTrue(ics.contains("URL:https://example.com\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
    }

    func testFoldsLongLines() {
        let folded = CalendarPlan.fold("SUMMARY:" + String(repeating: "a", count: 200))
        let lines = folded.components(separatedBy: "\r\n")
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count <= 75 })
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.hasPrefix(" ") })
    }

    func testFileName() {
        XCTAssertEqual(CalendarPlan.fileName(for: card("c", "Jazz / wine!", order: 1)), "Jazz  wine.ics")
        XCTAssertEqual(CalendarPlan.fileName(for: card("c", "!!!", order: 1)), "Event.ics")
    }
}
