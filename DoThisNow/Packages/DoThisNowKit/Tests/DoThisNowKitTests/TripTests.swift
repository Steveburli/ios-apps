import XCTest
@testable import DoThisNowKit

final class TripTests: XCTestCase {
    private let trip = Trip(id: "t", name: "Birthday", day: day(11, 14), startMinute: 600, endMinute: 1320)
    private let here = Coordinate(latitude: 41.88, longitude: -87.62)
    private let there = Coordinate(latitude: 41.89, longitude: -87.63)

    private func stop(_ id: String, stay: Int, fixed: Int? = nil, priority: Int = StopPriority.want, onDay: Bool = true,
                      order: Double, at coordinate: Coordinate? = nil, done: Bool = false) -> TripStop {
        TripStop(id: id, tripID: "t", title: id, coordinate: coordinate, stayMinutes: stay, fixedMinute: fixed,
                 priority: priority, onDay: onDay, order: order, done: done)
    }

    private func arrivals(_ schedule: TripSchedule) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: schedule.items.map { ($0.stop.id, $0.arrive) })
    }

    // MARK: Arrival times

    func testArrivalCountsTimeSpentAtEachStop() {
        let planner = TripPlanner(trip: trip, stops: [stop("a", stay: 30, order: 1), stop("b", stay: 60, order: 2)])
        let schedule = planner.schedule()
        XCTAssertEqual(arrivals(schedule), ["a": 600, "b": 630])
        XCTAssertEqual(schedule.finish, 690)
        XCTAssertEqual(schedule.overEnd, 0)
    }

    func testEachKindStartsWithItsOwnTimeSpent() {
        XCTAssertEqual(TripStop(tripID: "t", title: "Lunch", kind: .meal).stayMinutes, 75)
        XCTAssertEqual(TripStop(tripID: "t", title: "Gift", kind: .shop).stayMinutes, 30)
        XCTAssertEqual(TripStop(tripID: "t", title: "Gift", kind: .shop, stayMinutes: 10).stayMinutes, 10)
    }

    func testWalksUnderTheLimitAndDrivesOverIt() {
        let stops = [stop("a", stay: 30, order: 1, at: here), stop("b", stay: 30, order: 2, at: there)]
        let legs = [Leg.key(from: here, to: there): Leg(walkMinutes: 25, driveMinutes: 9)]
        var planner = TripPlanner(trip: trip, stops: stops, legs: legs)
        let walk = planner.schedule().item("b")!
        XCTAssertEqual(walk.travelMode, .walk)
        XCTAssertEqual(walk.arrive, 655)

        planner.trip.walkLimit = 20
        let drive = planner.schedule().item("b")!
        XCTAssertEqual(drive.travelMode, .drive)
        XCTAssertEqual(drive.arrive, 639)
    }

    func testMissingTravelTimesAreEstimatedFromDistance() {
        let planner = TripPlanner(trip: trip, stops: [stop("a", stay: 0, order: 1, at: here), stop("b", stay: 0, order: 2, at: there)])
        let b = planner.schedule().item("b")!
        XCTAssertTrue(b.travelIsEstimate)
        // About 1.4 km apart: roughly a 20-minute walk.
        XCTAssertEqual(b.travelMode, .walk)
        XCTAssertTrue((15...25).contains(b.travelMinutes), "\(b.travelMinutes)")
    }

    func testReorderingChangesEveryArrival() {
        var stops = [stop("a", stay: 30, order: 1), stop("b", stay: 60, order: 2)]
        stops[0].order = 3
        XCTAssertEqual(arrivals(TripPlanner(trip: trip, stops: stops).schedule()), ["b": 600, "a": 660])
    }

    // MARK: Fixed stops

    func testFixedStopsWaitForTheirTime() {
        let planner = TripPlanner(trip: trip, stops: [stop("a", stay: 30, order: 1), stop("show", stay: 120, fixed: 700, order: 2)])
        let show = planner.schedule().item("show")!
        XCTAssertEqual(show.arrive, 630)
        XCTAssertEqual(show.wait, 70)
        XCTAssertEqual(show.start, 700)
        XCTAssertEqual(show.leave, 820)
        XCTAssertTrue(planner.schedule().warnings.isEmpty)
    }

    func testLateForAFixedStopOffersToMoveOrDropAFlexibleOne() {
        let planner = TripPlanner(trip: trip, stops: [
            stop("museum", stay: 90, priority: StopPriority.top, order: 1),
            stop("shop", stay: 45, priority: StopPriority.maybe, order: 2),
            stop("show", stay: 120, fixed: 700, order: 3),
        ])
        let warning = planner.schedule().warnings.first!
        XCTAssertEqual(warning.fixedID, "show")
        XCTAssertEqual(warning.lateBy, 35)
        // The shop is least important, so it's offered first; dropping the museum alone works too.
        XCTAssertEqual(warning.fixes.first, .drop(stopID: "shop"))
        XCTAssertTrue(warning.fixes.contains(.moveAfter(stopID: "shop", fixedID: "show")))
        XCTAssertTrue(warning.fixes.contains(.drop(stopID: "museum")))

        let fixed = TripPlanner(trip: trip, stops: planner.applying(.moveAfter(stopID: "shop", fixedID: "show")))
        XCTAssertEqual(fixed.dayStops.map(\.id), ["museum", "show", "shop"])
        XCTAssertTrue(fixed.schedule().warnings.isEmpty)

        let dropped = TripPlanner(trip: trip, stops: planner.applying(.drop(stopID: "shop")))
        XCTAssertEqual(dropped.dayStops.map(\.id), ["museum", "show"])
        XCTAssertEqual(dropped.wishList.map(\.id), ["shop"])
    }

    func testFixedStopsStayInTimeOrder() {
        let day = [stop("dinner", stay: 90, fixed: 1140, order: 1), stop("walk", stay: 30, order: 2),
                   stop("show", stay: 120, fixed: 840, order: 3)]
        XCTAssertEqual(TripPlanner.sortingFixed(day).map(\.id), ["show", "walk", "dinner"])
    }

    func testWereHereStartsThePlanFromArrival() {
        var late = trip
        late.arrivedMinute = 660
        XCTAssertEqual(arrivals(TripPlanner(trip: late, stops: [stop("a", stay: 30, order: 1)]).schedule()), ["a": 660])
    }

    // MARK: Off schedule

    func testCatchUpPicksWhatFitsBeforeTheNextFixedStop() {
        let planner = TripPlanner(trip: trip, stops: [
            stop("show", stay: 120, fixed: 780, order: 1),
            stop("boat", stay: 240, priority: StopPriority.top, onDay: false, order: 1),
            stop("books", stay: 60, onDay: false, order: 2),
            stop("tower", stay: 90, onDay: false, order: 3),
            stop("park", stay: 60, priority: StopPriority.maybe, onDay: false, order: 4),
        ])
        let plan = planner.catchUp(now: 600, here: nil)
        XCTAssertEqual(plan.next?.id, "show")
        XCTAssertEqual(plan.available, 180)
        // The boat tour takes 4 hours and there are 3, but the two "want" stops fit.
        XCTAssertEqual(Set(plan.picks.map(\.id)), ["books", "tower"])
        XCTAssertEqual(plan.spare, 30)
        XCTAssertEqual(plan.skipped.map(\.stop.id), ["boat"])
        XCTAssertTrue(plan.skipped[0].tooLong)
        XCTAssertEqual(plan.plan.last?.stop.id, "show")
        XCTAssertFalse(plan.lateForNext)
    }

    func testCatchUpVisitsStopsInTheQuickestOrder() {
        let far = Coordinate(latitude: 41.95, longitude: -87.62)
        let planner = TripPlanner(trip: trip, stops: [
            stop("dinner", stay: 90, fixed: 1000, order: 1, at: far),
            stop("near", stay: 30, onDay: false, order: 1, at: there),
            stop("far", stay: 30, onDay: false, order: 2, at: far),
        ])
        let plan = planner.catchUp(now: 600, here: here)
        XCTAssertEqual(plan.picks.map(\.id), ["near", "far"])
        XCTAssertEqual(plan.plan.first?.arrive, 600 + plan.plan.first!.travelMinutes)
    }

    func testTakingTheCatchUpPlanRebuildsTheDay() {
        let planner = TripPlanner(trip: trip, stops: [
            stop("coffee", stay: 30, order: 1, done: true),
            stop("museum", stay: 200, order: 2),
            stop("show", stay: 120, fixed: 780, order: 3),
            stop("bar", stay: 60, order: 4),
            stop("books", stay: 60, onDay: false, order: 1),
        ])
        let plan = planner.catchUp(now: 660, here: nil)
        XCTAssertEqual(plan.picks.map(\.id), ["books"])
        let applied = planner.applying(plan)
        XCTAssertEqual(applied.trip.resumeMinute, 660)
        let after = TripPlanner(trip: applied.trip, stops: applied.stops)
        XCTAssertEqual(after.dayStops.map(\.id), ["coffee", "books", "show", "bar"])
        XCTAssertEqual(after.wishList.map(\.id), ["museum"])
        XCTAssertEqual(after.schedule().item("books")?.arrive, 660)
    }

    // MARK: Saved files

    func testOldOrPartialStopsStillLoad() throws {
        let json = #"{"id":"s","tripID":"t","title":"Lunch","kind":"meal"}"#
        let stop = try JSONDecoder().decode(TripStop.self, from: Data(json.utf8))
        XCTAssertEqual(stop.stayMinutes, 75)
        XCTAssertTrue(stop.onDay)
        XCTAssertNil(stop.fixedMinute)
        let unknown = try JSONDecoder().decode(TripStop.self, from: Data(#"{"kind":"zoo"}"#.utf8))
        XCTAssertEqual(unknown.kind, .other)
    }

    func testTheExampleTripHasNoWarnings() {
        let example = TripExample.make(on: day(11, 14))
        let schedule = TripPlanner(trip: example.trip, stops: example.stops).schedule()
        XCTAssertEqual(schedule.items.count, 6)
        XCTAssertTrue(schedule.warnings.isEmpty, "\(schedule.warnings)")
    }
}
