import XCTest
@testable import MutualKit

final class ItineraryTests: XCTestCase {
    func testOneLineWithThreeTimes() {
        let result = ItineraryText.parse("Dinner and a movie in Broad Ripple\nDrinks at 4 pm, movie at 6, dinner at 8")
        XCTAssertEqual(result.title, "Dinner and a movie in Broad Ripple")
        XCTAssertEqual(result.plan.area, "Broad Ripple")
        XCTAssertEqual(result.plan.stops.map(\.time), ["4:00 PM", "6:00 PM", "8:00 PM"])
        XCTAssertEqual(result.plan.stops.map(\.what), ["Drinks", "Movie", "Dinner"])
        XCTAssertEqual(result.plan.stops.map(\.place), ["", "", ""])
    }

    func testOneStopPerLineWithPlaces() {
        let text = """
        Fountain Square night
        4:00 PM – Drinks at Thunderbird, 1127 Shelby St
        6:30pm Movie @ The Fountain Theater
        9 p.m. Dinner: Siam Square
        Get the green curry
        """
        let result = ItineraryText.parse(text)
        XCTAssertEqual(result.title, "Fountain Square night")
        let stops = result.plan.stops
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(stops[0].time, "4:00 PM")
        XCTAssertEqual(stops[0].what, "Drinks")
        XCTAssertEqual(stops[0].place, "Thunderbird")
        XCTAssertEqual(stops[0].address, "1127 Shelby St")
        XCTAssertEqual(stops[1].time, "6:30 PM")
        XCTAssertEqual(stops[1].place, "The Fountain Theater")
        XCTAssertEqual(stops[2].time, "9:00 PM")
        XCTAssertEqual(stops[2].what, "Dinner")
        XCTAssertEqual(stops[2].place, "Siam Square")
        XCTAssertEqual(stops[2].note, "Get the green curry")
    }

    func testBulletsWithoutTimes() {
        let text = """
        Lazy Sunday
        - Brunch at Café Patachou
        - A walk on the Monon Trail
        - Ice cream
        """
        let result = ItineraryText.parse(text)
        XCTAssertEqual(result.title, "Lazy Sunday")
        XCTAssertEqual(result.plan.stops.map(\.headline), ["Brunch at Café Patachou", "A walk on the Monon Trail", "Ice cream"])
        XCTAssertEqual(result.plan.stops.map(\.time), ["", "", ""])
    }

    func testMorningWordsMakeBareTimesMorning() {
        let result = ItineraryText.parse("Brunch at 10:30, then coffee at 12")
        XCTAssertEqual(result.plan.stops.map(\.time), ["10:30 AM", "12:00 PM"])
        XCTAssertEqual(result.title, "Brunch and coffee")
    }

    func testLinksAreSkipped() {
        let result = ItineraryText.parse("https://example.com/plan/123\n7 pm Dinner at Milktooth")
        XCTAssertEqual(result.plan.stops.count, 1)
        XCTAssertEqual(result.plan.stops[0].place, "Milktooth")
        XCTAssertEqual(result.title, "Dinner")
    }

    func testStreetNumbersAreNotTimes() {
        XCTAssertTrue(ItineraryText.timeMatches(in: "Meet at 21 Main St").isEmpty)
        XCTAssertEqual(ItineraryText.timeMatches(in: "Meet at 9").count, 1)
    }

    func testMinutesAndFormat() {
        XCTAssertEqual(Itinerary.minutes(of: "4:00 PM"), 960)
        XCTAssertEqual(Itinerary.minutes(of: "12:15 am"), 15)
        XCTAssertEqual(Itinerary.minutes(of: "noon"), 720)
        XCTAssertEqual(Itinerary.minutes(of: "18:30"), 1110)
        XCTAssertNil(Itinerary.minutes(of: "later"))
        XCTAssertEqual(Itinerary.format(minutes: 960), "4:00 PM")
        XCTAssertEqual(Itinerary.format(minutes: 0), "12:00 AM")
        XCTAssertEqual(Itinerary.format(minutes: 1530), "1:30 AM")
    }

    func testCleaningKeepsSafePhotosAndDropsEmptyStops() {
        let plan = Itinerary(stops: [.init(id: "a", place: " Bazbeaux "), .init(id: "b"), .init(id: "c", what: "Walk", latitude: 39)],
                             photos: ["starter:d-bazbeaux", "photo:abc123.jpg", "photo:../x.jpg", "ftp://example.com/c.jpg",
                                      "http://example.com/a.jpg", "https://example.com/b.jpg", "starter:d-bazbeaux"])
        let clean = plan.cleaned()
        XCTAssertEqual(clean.stops.map(\.id), ["a", "c"])
        XCTAssertEqual(clean.stops[0].place, "Bazbeaux")
        XCTAssertNil(clean.stops[1].latitude, "Half a coordinate is dropped")
        XCTAssertEqual(clean.photos, ["starter:d-bazbeaux", "photo:abc123.jpg", "https://example.com/b.jpg"])
        XCTAssertEqual(clean.cleaned(), clean)
    }

    func testJSONRoundTripAndOldFields() {
        let plan = Itinerary(stops: [.init(id: "s1", time: "7:00 PM", what: "Dinner", place: "Milktooth", latitude: 39.75, longitude: -86.15)],
                             photos: ["starter:d-patachou"], area: "Fletcher Place")
        XCTAssertEqual(Itinerary.decode(plan.encoded()), plan)
        // A plan written by a later version with fields this one doesn't know still reads.
        let later = Itinerary.decode(#"{"stops":[{"id":"x","place":"Here","rating":5}],"mood":"cozy"}"#)
        XCTAssertEqual(later?.stops.first?.place, "Here")
        XCTAssertEqual(later?.photos, [])
        XCTAssertNil(Itinerary.decode(""))
    }

    func testSummaryAndSpan() {
        let plan = Itinerary(stops: [.init(time: "6:00 PM", what: "Dinner", place: "Siam Square"),
                                     .init(time: "9:00 PM", place: "HI-FI Indy", address: "1043 Virginia Ave")])
        XCTAssertEqual(plan.summary, "6:00 PM · Dinner at Siam Square\n9:00 PM · HI-FI Indy (1043 Virginia Ave)")
        XCTAssertEqual(plan.span, "2 stops · 6:00 PM to 9:00 PM")
    }

    func testCardDraftKeepsThePlan() {
        let plan = Itinerary(stops: [.init(id: "s", what: "Dinner")])
        let draft = CardText.clean(CardDraft(title: "Night out", plan: plan))
        XCTAssertEqual(draft?.plan, plan)
        let card = Card(groupID: "g", deckID: "d", draft: draft!, order: 0, createdAt: Date())
        XCTAssertEqual(card.plan, plan)
    }

    func testPlannedNightsUseBundledPhotosThatExist() {
        let bundled = Set(Starter.decks.flatMap(\.cards).filter(\.hasPhoto).map(\.id))
        for card in Starter.plannedNights {
            let plan = try! XCTUnwrap(card.plan)
            XCTAssertGreaterThanOrEqual(plan.stops.count, 2, card.id)
            XCTAssertTrue(plan.stops.allSatisfy { $0.minutes != nil }, card.id)
            for photo in plan.photos {
                guard case .starter(let id)? = PhotoRef(photo) else { return XCTFail("\(card.id): \(photo)") }
                XCTAssertTrue(bundled.contains(id), "\(card.id) uses \(id)")
            }
        }
        XCTAssertEqual(Starter.dates.sections.first, "Planned nights")
    }
}
