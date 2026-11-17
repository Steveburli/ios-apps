import XCTest
@testable import MutualKit

final class JourneyTests: XCTestCase {
    func testEveryStarterIDExists() {
        let ids = Set(Starter.decks.flatMap(\.cards).map(\.id))
        for category in Journey.activities {
            XCTAssertFalse(category.starterIDs.isEmpty, category.id)
            for id in category.starterIDs {
                XCTAssertTrue(ids.contains(id), "\(category.id) lists missing card \(id)")
            }
        }
        XCTAssertEqual(Set(Journey.activities.map(\.id)).count, Journey.activities.count)
    }

    /// Most kinds of food have Indy places; the rest lean on Apple Maps.
    func testEveryFoodHasPlacesOrAMapsSearch() {
        let answers = Journey.Answers(plan: .dinner)
        var withIndy = 0
        for food in Journey.foods {
            let count = Journey.indyPlaces(for: [food], answers: answers).count
            if count > 0 { withIndy += 1 }
            XCTAssertTrue(count > 0 || Journey.mapsWanted(for: food, indyCount: 0) > 0, food.title)
        }
        XCTAssertGreaterThanOrEqual(withIndy, 14)
    }

    func testDinnerPlanSwipesOnKindsOfFood() {
        let categories = Journey.categories(for: Journey.Answers(plan: .dinner))
        XCTAssertEqual(categories.map(\.title).first, "Pizza")
        XCTAssertFalse(categories.contains { $0.id == "museums" })
    }

    func testFamilyAndNoDrinkingLeaveOutBars() {
        let family = Journey.categories(for: Journey.Answers(plan: .nightOut, crowd: .family))
        XCTAssertFalse(family.contains { $0.id == "bars" })
        XCTAssertFalse(family.contains { $0.id == "music" })
        let dry = Journey.categories(for: Journey.Answers(plan: .nightOut, avoid: [.drinking]))
        XCTAssertFalse(dry.contains { $0.id == "bars" })
        let games = Journey.activities.first { $0.id == "games" }!
        let places = Journey.indyPlaces(for: [games], answers: Journey.Answers(avoid: [.drinking]))
        XCTAssertFalse(places.contains { $0.id == "n-pins" }, "Pins is 21+")
    }

    func testTripsOnlyWhenTheyllDrive() {
        let near = Journey.categories(for: Journey.Answers(plan: .weekend, distance: .city, when: .weekend))
        XCTAssertFalse(near.contains { $0.id == "daytrips" || $0.id == "getaways" })
        let far = Journey.categories(for: Journey.Answers(plan: .weekend, distance: .drive, when: .weekend))
        XCTAssertTrue(far.contains { $0.id == "getaways" })
        let tonight = Journey.categories(for: Journey.Answers(plan: .weekend, distance: .drive, when: .tonight))
        XCTAssertFalse(tonight.contains { $0.id == "getaways" })

        let museums = Journey.activities.first { $0.id == "museums" }!
        let close = Journey.indyPlaces(for: [museums], answers: Journey.Answers(distance: .close))
        XCTAssertFalse(close.contains { $0.id == "t-airforce" })
    }

    func testVibesSortBestMatchFirst() {
        let artsy = Journey.categories(for: Journey.Answers(plan: .date, vibes: [.artsy]))
        XCTAssertEqual(artsy.first?.id, "museums")
        let active = Journey.categories(for: Journey.Answers(plan: .date, vibes: [.active]))
        XCTAssertEqual(active.first?.id, "hiking")
    }

    func testBudgetFiltersByDollarSigns() {
        XCTAssertEqual(Journey.price(of: "Downtown · $$$$ · Steak"), 4)
        XCTAssertEqual(Journey.price(of: "Bottleworks District · $–$$"), 1)
        XCTAssertEqual(Journey.price(of: "North side · Free"), 0)
        XCTAssertNil(Journey.price(of: "1 hr · day"))
        let dinner = Journey.activities.first { $0.id == "dinner" }!
        let cheap = Journey.indyPlaces(for: [dinner], answers: Journey.Answers(budget: .cheap))
        XCTAssertFalse(cheap.isEmpty)
        XCTAssertFalse(cheap.contains { $0.id == "d-stelmo" })
    }

    func testPlacesAreTaggedCappedAndNotRepeated() {
        let answers = Journey.Answers(plan: .nightOut)
        let liked = Journey.activities.filter { $0.id == "games" || $0.id == "bars" || $0.id == "dinner" }
        let places = Journey.indyPlaces(for: liked, answers: answers)
        XCTAssertEqual(Set(places.map(\.id)).count, places.count, "Pins is in two categories but shows once")
        for category in liked {
            let mine = places.filter { $0.categoryID == category.id }
            XCTAssertLessThanOrEqual(mine.count, Journey.perCategory)
            for place in mine {
                XCTAssertEqual(place.draft.tags.first, category.title)
                XCTAssertEqual(CardText.clean(place.draft), place.draft, place.id)
            }
        }
        let dinner = Journey.activities.first { $0.id == "dinner" }!
        XCTAssertEqual(Journey.mapsWanted(for: dinner, indyCount: 8), 0)
        XCTAssertEqual(Journey.mapsWanted(for: dinner, indyCount: 1), 5)
        let stayIn = Journey.activities.first { $0.id == "stayin" }!
        XCTAssertEqual(Journey.mapsWanted(for: stayIn, indyCount: 0), 0)
    }

    func testDeckTitleAndBlurb() {
        let answers = Journey.Answers(plan: .date, crowd: .two, budget: .cheap, distance: .close, when: .weekend,
                                      vibes: [.cozy, .chill])
        XCTAssertEqual(Journey.deckTitle(for: answers), "This weekend: date")
        let blurb = Journey.deckBlurb(for: answers)
        XCTAssertEqual(blurb, "Planned in Mutual · Just the two of us · keep it cheap · close by · chill, cozy")
        XCTAssertTrue(Journey.isPlanned(blurb: blurb))
        XCTAssertFalse(Journey.isPlanned(blurb: "Indianapolis restaurants"))
    }
}
