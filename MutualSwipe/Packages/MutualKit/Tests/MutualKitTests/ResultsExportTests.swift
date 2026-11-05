import XCTest
@testable import MutualKit

final class ResultsExportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func card(_ id: String, _ title: String, order: Double) -> Card {
        Card(id: id, groupID: "g", deckID: "d", draft: CardDraft(title: title), order: order, createdAt: start)
    }

    private func pick(_ cardID: String, _ playerID: String, _ vote: Vote) -> Pick {
        Pick(groupID: "g", deckID: "d", cardID: cardID, playerID: playerID, vote: vote, updatedAt: start)
    }

    func testCSV() {
        let cards = [
            card("c2", "Pierogi, crispy", order: 2),
            card("c1", "Chicken \"pot\" pie", order: 1),
            card("c3", "Fish tacos", order: 3),
            card("c4", "Soup", order: 4),
        ]
        let players = [
            Player(id: "a", groupID: "g", name: "A", color: 0, createdAt: start),
            Player(id: "b", groupID: "g", name: "B", color: 1, createdAt: start.addingTimeInterval(1)),
        ]
        let picks = [
            pick("c1", "a", .love), pick("c1", "b", .love),
            pick("c2", "a", .like), pick("c2", "b", .nope),
            pick("c3", "a", .never),
            pick("c4", "a", .like),
        ]
        let state = DeckState(cards: cards, players: players, picks: picks, me: "a")
        XCTAssertEqual(ResultsExport.csv(state), """
        title,result
        "Chicken ""pot"" pie",Super match
        "Pierogi, crispy",Split
        Fish tacos,Trash
        Soup,Waiting on votes

        """)
        XCTAssertTrue(ResultsExport.hasResults(state))
    }

    func testNoResultsYet() {
        let state = DeckState(cards: [card("c1", "Soup", order: 1)], players: [], picks: [], me: nil)
        XCTAssertFalse(ResultsExport.hasResults(state))
    }

    func testCellFlattensLines() {
        XCTAssertEqual(ResultsExport.cell("a\nb"), "a b")
        XCTAssertEqual(ResultsExport.cell(" padded"), "\" padded\"")
    }
}
