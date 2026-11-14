import XCTest
@testable import DoThisNowKit

final class PlaceTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Home and the gym, with "start Gym when I leave Home" and "stop Gym when I leave the gym".
    private func gymState() -> PlannerState {
        var state = PlannerState()
        state.activities = [Activity(id: "gym", name: "Gym", symbol: "dumbbell"),
                            Activity(id: "chores", name: "Chores")]
        state.placeTimers.places = [
            WatchedPlace(id: "home", name: "Home", coordinate: Coordinate(latitude: 39.77, longitude: -86.15)),
            WatchedPlace(id: "club", name: "the gym", coordinate: Coordinate(latitude: 39.80, longitude: -86.10)),
        ]
        state.placeTimers.rules = [
            PlaceRule(id: "r1", activityID: "gym", action: .start, crossing: .leave, placeID: "home"),
            PlaceRule(id: "r2", activityID: "gym", action: .stop, crossing: .leave, placeID: "club"),
        ]
        return state
    }

    func testLeavingHomeStartsAndLeavingTheGymStops() {
        var state = gymState()
        let started = state.crossed(placeID: "home", .leave, at: t0)
        XCTAssertEqual(started.map(\.action), [.start])
        XCTAssertEqual(state.running?.activityID, "gym")
        XCTAssertEqual(state.running?.startedAt, t0)
        XCTAssertEqual(state.placeCheckDue, t0.addingTimeInterval(3600))

        // Arriving at the gym does nothing: no rule for it.
        XCTAssertTrue(state.crossed(placeID: "club", .arrive, at: t0.addingTimeInterval(900)).isEmpty)

        let stopped = state.crossed(placeID: "club", .leave, at: t0.addingTimeInterval(5400))
        XCTAssertEqual(stopped.map(\.action), [.stop])
        XCTAssertNil(state.running)
        XCTAssertEqual(state.timings.last?.seconds, 5400)
        XCTAssertNil(state.placeCheckDue)
        XCTAssertEqual(state.placeTimers.history.count, 2)
        XCTAssertEqual(stopped.first?.summary, "Gym stopped: left the gym")
    }

    func testStopOnlyStopsItsOwnTimer() {
        var state = gymState()
        state.startTimer(activityID: "chores", title: "Chores", at: t0)
        XCTAssertTrue(state.crossed(placeID: "club", .leave, at: t0.addingTimeInterval(600)).isEmpty)
        XCTAssertEqual(state.running?.activityID, "chores")
    }

    func testRulesThatAreOffOrForUnknownPlacesDoNothing() {
        var state = gymState()
        state.placeTimers.rules[0].on = false
        XCTAssertTrue(state.crossed(placeID: "home", .leave, at: t0).isEmpty)
        XCTAssertTrue(state.crossed(placeID: "nowhere", .leave, at: t0).isEmpty)
        XCTAssertNil(state.running)
        XCTAssertEqual(state.placeTimers.watchedPlaces.map(\.id), ["club"])
    }

    func testUndoingAStartPutsBackWhatWasRunning() {
        var state = gymState()
        state.startTimer(activityID: "chores", title: "Chores", at: t0)
        let firing = state.crossed(placeID: "home", .leave, at: t0.addingTimeInterval(1200))[0]
        XCTAssertEqual(state.timings.count, 1, "Chores was saved when Gym started")
        XCTAssertTrue(state.undo(firingID: firing.id))
        XCTAssertEqual(state.running?.activityID, "chores")
        XCTAssertEqual(state.running?.startedAt, t0)
        XCTAssertTrue(state.timings.isEmpty)
        XCTAssertNil(state.placeCheckDue)
        XCTAssertFalse(state.undo(firingID: firing.id), "Undo works once")
    }

    func testUndoingAStopKeepsTheTimerGoing() {
        var state = gymState()
        state.crossed(placeID: "home", .leave, at: t0)
        let stop = state.crossed(placeID: "club", .leave, at: t0.addingTimeInterval(3000))[0]
        XCTAssertTrue(state.undo(firingID: stop.id))
        XCTAssertEqual(state.running?.startedAt, t0)
        XCTAssertTrue(state.timings.isEmpty)
    }

    func testNoUndoOnceYouChangedTheTimerYourself() {
        var state = gymState()
        let start = state.crossed(placeID: "home", .leave, at: t0)[0]
        state.stopTimer(at: t0.addingTimeInterval(600))
        XCTAssertFalse(state.canUndo(start))
        XCTAssertFalse(state.undo(firingID: start.id))
    }

    func testKeepGoingAsksAgainAnHourLater() {
        var state = gymState()
        state.crossed(placeID: "home", .leave, at: t0)
        let later = t0.addingTimeInterval(3700)
        state.postponePlaceCheck(from: later)
        XCTAssertEqual(state.placeCheckDue, later.addingTimeInterval(3600))
        // Switching to another timer by hand drops the question.
        state.startTimer(activityID: "chores", title: "Chores", at: later)
        XCTAssertNil(state.placeCheckDue)
    }

    func testDeletingAPlaceOrActivityRemovesItsRules() {
        var state = gymState()
        state.deleteWatchedPlace("home")
        XCTAssertEqual(state.placeTimers.rules.map(\.id), ["r2"])
        state.deleteActivity("gym")
        XCTAssertTrue(state.placeTimers.rules.isEmpty)
    }

    func testOldFilesLoadAndPlacesRoundTrip() throws {
        let old = try JSONDecoder().decode(PlannerState.self, from: Data("{}".utf8))
        XCTAssertTrue(old.placeTimers.places.isEmpty)

        var state = gymState()
        state.crossed(placeID: "home", .leave, at: t0)
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(PlannerState.self, from: data)
        XCTAssertEqual(back.placeTimers, state.placeTimers)
    }
}
