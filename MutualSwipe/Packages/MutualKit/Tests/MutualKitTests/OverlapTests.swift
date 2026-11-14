import XCTest
@testable import MutualKit

final class OverlapTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func card(_ id: String, order: Double) -> Card {
        Card(id: id, groupID: "g", deckID: "d", draft: CardDraft(title: "Card \(id)"), order: order, createdAt: start)
    }

    private func pick(_ cardID: String, _ playerID: String, _ vote: Vote) -> Pick {
        Pick(groupID: "g", deckID: "d", cardID: cardID, playerID: playerID, vote: vote, updatedAt: start)
    }

    private func player(_ id: String, _ offset: TimeInterval) -> Player {
        Player(id: id, groupID: "g", name: id.uppercased(), color: 0, createdAt: start.addingTimeInterval(offset))
    }

    /// a, b, c, d vote on four cards.
    private func sample() -> DeckState {
        let cards = [card("c1", order: 1), card("c2", order: 2), card("c3", order: 3), card("c4", order: 4)]
        let players = [player("a", 0), player("b", 1), player("c", 2), player("d", 3)]
        let picks = [
            pick("c1", "a", .love), pick("c1", "b", .like), pick("c1", "c", .like),
            pick("c2", "a", .like), pick("c2", "b", .love), pick("c2", "c", .nope),
            pick("c3", "a", .nope), pick("c3", "b", .like), pick("c3", "c", .love),
            pick("c4", "a", .nope), pick("c4", "b", .nope), pick("c4", "c", .nope), pick("c4", "d", .love),
            pick("c1", "d", .nope),
        ]
        return DeckState(cards: cards, players: players, picks: picks, me: "a")
    }

    func testStartingCardsAreMostLiked() {
        // c1 has 3 fans; c2 and c3 have 2 each with one super like; c4 has 1.
        XCTAssertEqual(Overlap.startingCards(sample()), ["c1", "c2", "c3"])
        XCTAssertEqual(Overlap.startingCards(sample(), count: 1), ["c1"])
    }

    func testStartingCardsSkipCardsNobodyLiked() {
        let state = DeckState(cards: [card("c1", order: 1), card("c2", order: 2)], players: [player("a", 0)],
                              picks: [pick("c1", "a", .nope), pick("c2", "a", .like)], me: "a")
        XCTAssertEqual(Overlap.startingCards(state), ["c2"])
    }

    func testMembershipAndAreas() {
        let state = sample()
        let shown = ["c1", "c2", "c3"]
        let inside = Overlap.membership(state, shown: shown)
        XCTAssertEqual(inside["a"], [0, 1])
        XCTAssertEqual(inside["b"], [0, 1, 2])
        XCTAssertEqual(inside["c"], [0, 2])
        XCTAssertEqual(inside["d"], [])
        XCTAssertEqual(Overlap.people(in: [0, 1], state: state, shown: shown), ["a"])
        XCTAssertEqual(Overlap.people(in: [], state: state, shown: shown), ["d"])
    }

    func testPeopleLikingAll() {
        let state = sample()
        XCTAssertEqual(Overlap.people(likingAll: ["c1"], state: state), ["a", "b", "c"])
        XCTAssertEqual(Overlap.people(likingAll: ["c1", "c2"], state: state), ["a", "b"])
        XCTAssertEqual(Overlap.people(likingAll: ["c1", "c2", "c3"], state: state), ["b"])
        XCTAssertEqual(Overlap.people(likingAll: [], state: state), [])
    }

    func testOnlyLovedBy() {
        let state = sample()
        XCTAssertEqual(Overlap.onlyLovedBy("d", in: state).map(\.id), ["c4"])
        // a super liked c1, but b and c liked it too.
        XCTAssertEqual(Overlap.onlyLovedBy("a", in: state).map(\.id), [])
        // b super liked c2 and a liked it.
        XCTAssertEqual(Overlap.onlyLovedBy("b", in: state).map(\.id), [])
    }

    func testRetiredCardsAreLeftOut() {
        var retired = card("c1", order: 1)
        retired.retiredAt = start
        let state = DeckState(cards: [retired, card("c2", order: 2)], players: [player("a", 0)],
                              picks: [pick("c1", "a", .love), pick("c2", "a", .love)], me: "a")
        XCTAssertEqual(Overlap.startingCards(state), ["c2"])
        XCTAssertEqual(Overlap.onlyLovedBy("a", in: state).map(\.id), ["c2"])
    }

    func testInviteNamesOnlyTheCard() {
        let message = Overlap.inviteMessage(for: card("c1", order: 1), kind: .dates)
        XCTAssertTrue(message.contains("Card c1"))
        for kind in DeckKind.allCases {
            XCTAssertFalse(Overlap.inviteMessage(for: card("c1", order: 1), kind: kind).isEmpty)
        }
    }
}
