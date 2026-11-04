import XCTest
@testable import MutualKit

final class RoundsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func card(_ id: String, order: Double, tags: [String] = []) -> Card {
        Card(id: id, groupID: "g", deckID: "d", draft: CardDraft(title: id, tags: tags), order: order, createdAt: start)
    }

    private func player(_ id: String, joined: Double) -> Player {
        Player(id: id, groupID: "g", name: id.capitalized, color: 0, createdAt: start.addingTimeInterval(joined))
    }

    private func pick(_ cardID: String, _ playerID: String, _ vote: Vote) -> Pick {
        Pick(groupID: "g", deckID: "d", cardID: cardID, playerID: playerID, vote: vote, updatedAt: start)
    }

    private lazy var cards = [card("tacos", order: 1, tags: ["mexican"]), card("pasta", order: 2, tags: ["italian"]),
                              card("pho", order: 3), card("pizza", order: 4, tags: ["italian"])]
    private lazy var players = [player("al", joined: 0), player("bea", joined: 10)]

    func testRoundPickIDsStaySeparateFromVetting() {
        let vetting = Pick(groupID: "g", deckID: "d", cardID: "c", playerID: "p", vote: .like, updatedAt: start)
        let round = Pick(groupID: "g", deckID: "d", cardID: "c", playerID: "p", vote: .never, updatedAt: start, roundID: "r1")
        XCTAssertEqual(vetting.id, "pick_c_p")
        XCTAssertEqual(round.id, "pick_c_p_rr1")
        XCTAssertNil(vetting.roundID)
        XCTAssertEqual(round.roundID, "r1")
        XCTAssertEqual(Vote.never.label(round: true), "Not tonight")
        XCTAssertEqual(Vote.never.label(round: false), "Never")
    }

    func testVettingShares() {
        // Al swiped everything; Bea swiped one card; Cy never opened the deck.
        let picks = cards.map { pick($0.id, "al", .like) } + [pick("tacos", "bea", .love)]
        let all = players + [player("cy", joined: 20)]
        let state = DeckState(cards: cards, players: all, picks: picks, me: "al")
        let vetting = Vetting(state: state, players: all.map(\.id))
        XCTAssertEqual(vetting.share["al"], 1)
        XCTAssertEqual(vetting.share["bea"], 0.25)
        XCTAssertEqual(vetting.share["cy"], 0)
        XCTAssertEqual(vetting.vetted, ["al"])
        XCTAssertEqual(vetting.group, 5.0 / 12.0, accuracy: 0.0001)
        XCTAssertEqual(Vetting.percent(vetting.group), "41%")
        XCTAssertEqual(Vetting.percent(0.996), "99%")
    }

    func testANeverFromSomeoneElseCountsAsDone() {
        let picks = [pick("tacos", "al", .never), pick("pasta", "bea", .like), pick("pho", "bea", .like), pick("pizza", "bea", .like)]
        let state = DeckState(cards: cards, players: players, picks: picks, me: "bea")
        XCTAssertEqual(Vetting(state: state, players: ["al", "bea"]).vetted, ["bea"])
    }

    func testANewCardTakesAwayVetted() {
        let picks = cards.flatMap { c in ["al", "bea"].map { pick(c.id, $0, .like) } }
        let before = DeckState(cards: cards, players: players, picks: picks, me: "al")
        XCTAssertEqual(Vetting(state: before, players: ["al", "bea"]).vetted, ["al", "bea"])
        let after = DeckState(cards: cards + [card("ramen", order: 5)], players: players, picks: picks, me: "al")
        let vetting = Vetting(state: after, players: ["al", "bea"])
        XCTAssertEqual(vetting.vetted, [])
        XCTAssertEqual(vetting.group, 0.8, accuracy: 0.0001)
    }

    func testVettedDeckRoundUsesOnlyWhatEveryoneLikes() {
        let votes: [(String, Vote, Vote)] = [("tacos", .love, .like), ("pasta", .like, .nope), ("pho", .like, .like), ("pizza", .never, .love)]
        let picks = votes.flatMap { [pick($0.0, "al", $0.1), pick($0.0, "bea", $0.2)] }
        let state = DeckState(cards: cards, players: players, picks: picks, me: "al")
        let plan = Rounds.plan(vetting: state)
        XCTAssertTrue(plan.usesVetting)
        XCTAssertEqual(plan.cards.map(\.id), ["tacos", "pho"])
    }

    func testUnvettedDeckRoundUsesAllButNevers() {
        let picks = [pick("tacos", "al", .like), pick("pizza", "bea", .never)]
        let state = DeckState(cards: cards, players: players, picks: picks, me: "al")
        let plan = Rounds.plan(vetting: state)
        XCTAssertFalse(plan.usesVetting)
        XCTAssertEqual(plan.cards.map(\.id), ["tacos", "pasta", "pho"])
        // Nobody has swiped at all: every card.
        XCTAssertEqual(Rounds.plan(vetting: DeckState(cards: cards, players: players, picks: [], me: "al")).cards.count, 4)
    }

    func testChainFilterNarrowsWhenSomethingMatches() {
        let state = DeckState(cards: cards, players: players, picks: [], me: "al")
        let italian = Rounds.plan(vetting: state, filter: ["Italian"])
        XCTAssertEqual(italian.cards.map(\.id), ["pasta", "pizza"])
        XCTAssertEqual(italian.narrowedBy, ["Italian"])
        // Nothing mentions it, so the round keeps every card.
        let thai = Rounds.plan(vetting: state, filter: ["Thai"])
        XCTAssertEqual(thai.cards.count, 4)
        XCTAssertEqual(thai.narrowedBy, [])
    }

    func testWinnerAndHistory() {
        let picks = [pick("tacos", "al", .like), pick("tacos", "bea", .like),
                     pick("pho", "al", .love), pick("pho", "bea", .love), pick("pasta", "al", .love), pick("pasta", "bea", .like)]
        let state = DeckState(cards: cards, players: players, picks: picks, me: "al")
        XCTAssertEqual(Rounds.winner(of: state, decided: [], spin: nil)?.id, "pho")
        XCTAssertEqual(Rounds.winner(of: state, decided: [], spin: "tacos")?.id, "tacos")
        XCTAssertEqual(Rounds.winner(of: state, decided: ["pasta"], spin: "tacos")?.id, "pasta")
        XCTAssertNil(Rounds.winner(of: DeckState(cards: cards, players: players, picks: [], me: "al"), decided: [], spin: nil))

        var history: [RoundResult] = []
        history = Rounds.record(RoundResult(roundID: "r1", question: "Tonight?", cardID: "pho", title: "pho", at: start), in: history)
        history = Rounds.record(RoundResult(roundID: "r2", question: "Tonight?", cardID: "tacos", title: "tacos", at: start.addingTimeInterval(86_400)), in: history)
        // Changing round 1's winner replaces it instead of adding a second.
        history = Rounds.record(RoundResult(roundID: "r1", question: "Tonight?", cardID: "pasta", title: "pasta", at: start.addingTimeInterval(60)), in: history)
        XCTAssertEqual(history.map(\.cardID), ["pasta", "tacos"])
    }
}
