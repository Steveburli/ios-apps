import XCTest
@testable import MutualKit

final class ResultsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func card(_ id: String, order: Double) -> Card {
        Card(id: id, groupID: "g", deckID: "d", draft: CardDraft(title: id), order: order, createdAt: start)
    }

    private func player(_ id: String, joined: Double) -> Player {
        Player(id: id, groupID: "g", name: id.capitalized, color: 0, createdAt: start.addingTimeInterval(joined))
    }

    private func pick(_ cardID: String, _ playerID: String, _ vote: Vote) -> Pick {
        Pick(groupID: "g", deckID: "d", cardID: cardID, playerID: playerID, vote: vote, updatedAt: start)
    }

    func testClassify() {
        let both = ["a", "b"]
        func verdict(_ a: Vote?, _ b: Vote?) -> Verdict {
            var picks: [String: [String: Vote]] = ["a": [:], "b": [:]]
            picks["a"]?["c"] = a
            picks["b"]?["c"] = b
            return DeckState.classify("c", participants: both, picks: picks)
        }
        XCTAssertEqual(verdict(.love, .love), .perfect)
        XCTAssertEqual(verdict(.love, .like), .match)
        XCTAssertEqual(verdict(.like, .like), .match)
        XCTAssertEqual(verdict(.love, .nope), .debate)
        XCTAssertEqual(verdict(.like, .nope), .split)
        XCTAssertEqual(verdict(.nope, .nope), .trash)
        XCTAssertEqual(verdict(.love, .never), .trash)
        XCTAssertEqual(verdict(.like, nil), .pending)
        // A super reject decides it even before everyone votes.
        XCTAssertEqual(verdict(.never, nil), .trash)
        XCTAssertEqual(DeckState.classify("c", participants: [], picks: [:]), .pending)
    }

    func testDeckState() {
        let cards = [card("c2", order: 2), card("c1", order: 1), card("c3", order: 3)]
        let players = [player("bea", joined: 10), player("al", joined: 0), player("cy", joined: 20)]
        let picks = [
            pick("c1", "al", .love), pick("c1", "bea", .love),
            pick("c2", "al", .like),
            pick("c3", "bea", .never),
            pick("other-deck-card", "cy", .like),
        ]
        let state = DeckState(cards: cards, players: players, picks: picks, me: "al")

        XCTAssertEqual(state.cards.map(\.id), ["c1", "c2", "c3"])
        // Cy only voted in another deck, so isn't part of this one.
        XCTAssertEqual(state.participants, ["al", "bea"])
        XCTAssertEqual(state.cards(.perfect).map(\.id), ["c1"])
        XCTAssertEqual(state.cards(.pending).map(\.id), ["c2"])
        XCTAssertEqual(state.cards(.trash).map(\.id), ["c3"])
        XCTAssertEqual(state.matchCount, 1)
        // Bea's super reject takes c3 out of Al's stack.
        XCTAssertEqual(state.queue.map(\.id), [])
        XCTAssertEqual(state.remaining(for: "bea"), 1)
        XCTAssertEqual(state.progress["al"], 2)
        XCTAssertEqual(state.vote(of: "al", on: "c2"), .like)
    }

    func testYouAreAParticipantBeforeYourFirstSwipe() {
        let state = DeckState(cards: [card("c1", order: 1)], players: [player("al", joined: 0)], picks: [], me: "al")
        XCTAssertEqual(state.participants, ["al"])
        XCTAssertEqual(state.queue.map(\.id), ["c1"])
        XCTAssertTrue(state.activeParticipants.isEmpty)

        let nobody = DeckState(cards: [card("c1", order: 1)], players: [], picks: [], me: nil)
        XCTAssertEqual(nobody.queue.count, 1)
    }

    func testTierTitles() {
        XCTAssertEqual(Verdict.perfect.title(people: 2), "You both super liked")
        XCTAssertEqual(Verdict.match.title(people: 3), "Everyone’s in")
        XCTAssertTrue(Verdict.trash.startsCollapsed)
    }

    func testNextColor() {
        let players = [player("a", joined: 0), player("b", joined: 1)]
        var colored = players
        colored[1].color = 1
        XCTAssertEqual(Player.nextColor(after: colored), 2)
        XCTAssertEqual(Player.nextColor(after: []), 0)
    }
}

final class CardTextTests: XCTestCase {
    func testClean() {
        let draft = CardText.clean(title: "  Past Lives ", subtitle: "2023 · drama", link: "example.com/film", tags: "quiet, , sad ,a,b,c,d,e")
        XCTAssertEqual(draft?.title, "Past Lives")
        XCTAssertEqual(draft?.link, "https://example.com/film")
        XCTAssertEqual(draft?.tags, ["quiet", "sad", "a", "b", "c", "d"])
        XCTAssertNil(CardText.clean(title: "   "))
        XCTAssertEqual(CardText.clean(title: String(repeating: "x", count: 200))?.title.count, 120)
    }

    func testSafeURL() {
        XCTAssertEqual(CardText.safeURL(""), "")
        XCTAssertEqual(CardText.safeURL("http://a.com"), "http://a.com")
        XCTAssertEqual(CardText.safeURL("javascript://alert(1)"), "")
        XCTAssertEqual(CardText.safeURL("ftp://files.com"), "")
        XCTAssertEqual(CardText.host("https://www.nytimes.com/2026/a"), "nytimes.com")
    }

    func testInitial() {
        XCTAssertEqual(CardText.initial("The Bear"), "B")
        XCTAssertEqual(CardText.initial("an evening out"), "E")
        XCTAssertEqual(CardText.initial("Theater night"), "T")
        XCTAssertEqual(CardText.initial("  "), "?")
        XCTAssertEqual(CardText.initial("éclair"), "É")
    }

    func testColorIndexMatchesTheWebApp() {
        // h = 7 × 31 + 97 = 314, and 314 mod 8 = 2.
        XCTAssertEqual(CardText.colorIndex("a"), 2)
        XCTAssertEqual(CardText.colorIndex("same"), CardText.colorIndex("same"))
        XCTAssertTrue((0..<8).contains(CardText.colorIndex("a long seed that overflows 32 bits many times")))
    }

    func testParseList() {
        let text = """
        - Thai green curry | Thai · 40 min | Coconut, basil, a little heat
        2. Tacos | Mexican

        • Ramen
        """
        let drafts = CardText.parseList(text)
        XCTAssertEqual(drafts.map(\.title), ["Thai green curry", "Tacos", "Ramen"])
        XCTAssertEqual(drafts[0].subtitle, "Thai · 40 min")
        XCTAssertEqual(drafts[0].details, "Coconut, basil, a little heat")
        XCTAssertEqual(drafts[1].subtitle, "Mexican")
    }

    func testPickIDsAreStable() {
        XCTAssertEqual(Pick.id(cardID: "c1", playerID: "p1"), "pick_c1_p1")
        XCTAssertEqual(makeID().count, 32)
    }
}
