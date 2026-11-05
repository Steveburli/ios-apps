import XCTest
@testable import MutualKit

final class StarterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    func testEveryCardSurvivesCleaningUnchanged() {
        for deck in Starter.decks {
            XCTAssertFalse(deck.cards.isEmpty, deck.title)
            for card in deck.cards {
                let clean = CardText.clean(card.draft)
                XCTAssertEqual(clean, card.draft, card.id)
                if !card.website.isEmpty {
                    XCTAssertEqual(CardText.safeURL(card.website), card.website, card.id)
                }
            }
        }
    }

    func testIDsAndPhotoNamesAreUnique() {
        let ids = Starter.decks.flatMap(\.cards).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(Starter.decks.map(\.id)).count, Starter.decks.count)
        let photos = Starter.decks.flatMap(\.cards).compactMap(\.photoName)
        XCTAssertEqual(Set(photos).count, photos.count)
        XCTAssertEqual(photos.count, 50)
    }

    /// A round chained from "What should we eat?" into Dinners narrows by the
    /// winner's title, so every Dinners tag must be one of the meal titles.
    func testDinnerTagsAreMealTitles() {
        let meals = Set(Starter.meals.cards.map(\.title))
        for card in Starter.dinners.cards {
            for tag in card.tags {
                XCTAssertTrue(meals.contains(tag), "\(card.id) has tag \(tag)")
            }
        }
    }

    func testChainingPizzaNarrowsDinnersToPizzaPlaces() {
        let cards = Starter.dinners.cards.enumerated().map { index, starter in
            Card(id: starter.id, groupID: "g", deckID: "d", draft: starter.draft, order: Double(index), createdAt: start)
        }
        let state = DeckState(cards: cards, players: [], picks: [], me: nil)
        let plan = Rounds.plan(vetting: state, filter: ["Pizza"])
        XCTAssertEqual(Set(plan.cards.map(\.id)), ["d-bazbeaux", "d-kingdough", "d-garage"])
        XCTAssertEqual(plan.narrowedBy, ["Pizza"])
    }

    func testSectionsKeepFirstSeenOrder() {
        XCTAssertEqual(Starter.trips.sections, ["Day trip", "Weekend"])
        XCTAssertEqual(Starter.meals.sections, ["Eat out", "At home"])
    }

    func testCopiedCardsFindTheirStarterByLinkOrTitle() {
        let elmo = Starter.dinners.cards[0]
        var draft = elmo.draft
        draft.link = "http://stelmos.com"
        let copied = Card(groupID: "g", deckID: "d", draft: draft, order: 0, createdAt: start)
        XCTAssertEqual(Starter.match(copied)?.id, elmo.id)
        XCTAssertEqual(Starter.match(copied)?.photoName, "starter-d-stelmo")

        let noLink = Card(groupID: "g", deckID: "d", draft: CardDraft(title: "st. elmo steak house"), order: 0, createdAt: start)
        XCTAssertEqual(Starter.match(noLink)?.id, elmo.id)

        let other = Card(groupID: "g", deckID: "d", draft: CardDraft(title: "Pizza", link: "https://example.com"), order: 0,
                         createdAt: start)
        XCTAssertNil(Starter.match(other))
    }

    func testDraftPutsGoodForAndWhatToDoInDetails() {
        let draft = Starter.dinners.cards[0].draft
        XCTAssertTrue(draft.details.contains("\n\nGood for: "))
        XCTAssertTrue(draft.details.contains("\nWhat to do: "))
        XCTAssertEqual(draft.subtitle, "Downtown · $$$$ · Steak")
    }
}
