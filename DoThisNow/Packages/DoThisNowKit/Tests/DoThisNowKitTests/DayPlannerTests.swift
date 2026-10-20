import XCTest
@testable import DoThisNowKit

final class DayPlannerTests: XCTestCase {
    private func spans(_ pairs: [(Double, Double)]) -> [TimeSpan] {
        pairs.map { TimeSpan(start: $0.0, end: $0.1) }
    }

    func testFreeSlots() {
        let busy = spans([(60, 120), (100, 150), (300, 400)])
        XCTAssertEqual(DayPlanner.freeSlots(busy, from: 0, to: 500), spans([(0, 60), (150, 300), (400, 500)]))
        XCTAssertEqual(DayPlanner.freeSlots(busy, from: 70, to: 140), [])
    }

    func testPlaceSplitsAcrossGaps() {
        var busy = spans([(60, 120)])
        let placed = DayPlanner.place(&busy, from: 0, to: 300, need: 90, minPiece: 30)
        XCTAssertEqual(placed.pieces, spans([(0, 60), (120, 150)]))
        XCTAssertEqual(placed.left, 0)
        XCTAssertEqual(busy.count, 3)
    }

    func testPlaceNeverLeavesASliverBehind() {
        // 40 free minutes would leave 10, under the 30-minute minimum, so it
        // takes 20, which is too small, and moves on to the next gap.
        var busy = spans([(40, 100)])
        let placed = DayPlanner.place(&busy, from: 0, to: 300, need: 50, minPiece: 30)
        XCTAssertEqual(placed.pieces, spans([(100, 150)]))
    }

    func testCarve() {
        XCTAssertEqual(DayPlanner.carve(TimeSpan(start: 540, end: 1020), 600, 700), spans([(540, 600), (700, 1020)]))
        XCTAssertEqual(DayPlanner.carve(TimeSpan(start: 540, end: 1020), 500, 1100), [])
    }

    func testAnEmptyWorkday() {
        let plan = engine(PlannerState()).planDay(day(10, 15)) // Thursday
        XCTAssertFalse(plan.isToday)
        XCTAssertEqual(plan.rocks, spans([(540, 1020)]))
        XCTAssertEqual(plan.meal, TimeSpan(start: 1110, end: 1145))
        XCTAssertEqual(plan.sleepStart, 1380)
        XCTAssertEqual(plan.push, 0)
        // 16 waking hours minus 8 of work and 35 minutes of dinner.
        XCTAssertEqual(plan.free, 445)
    }

    func testEventsOverWorkBecomeGhostsUnlessYouTakeTimeOff() {
        var state = PlannerState()
        state.events = [PlannerEvent(id: "lunch", title: "Lunch", day: day(10, 15), start: 720, end: 780, minStay: 60, travel: 0)]
        var plan = engine(state).planDay(day(10, 15))
        XCTAssertEqual(plan.ghostEvents.map(\.id), ["lunch"])
        XCTAssertEqual(plan.ghostEvents.first?.ghost?.reason, .work)
        XCTAssertTrue(plan.live.isEmpty)

        state.events[0].overWork = true
        plan = engine(state).planDay(day(10, 15))
        XCTAssertEqual(plan.live.map(\.id), ["lunch"])
        XCTAssertEqual(plan.rocks, spans([(540, 720), (780, 1020)]))
    }

    func testClashingEventsAndTheLastOneMovedWins() {
        var state = PlannerState()
        state.events = [
            PlannerEvent(id: "a", title: "A", day: day(10, 17), start: 600, end: 720, minStay: 60, travel: 0),
            PlannerEvent(id: "b", title: "B", day: day(10, 17), start: 630, end: 720, minStay: 60, travel: 0),
        ]
        var e = engine(state)
        XCTAssertEqual(e.planDay(day(10, 17)).live.map(\.id), ["a"])
        XCTAssertEqual(e.planDay(day(10, 17)).ghostEvents.first?.ghost?.text, "Clashes with A")
        e.preferredEventID = "b"
        XCTAssertEqual(e.planDay(day(10, 17)).live.map(\.id), ["b"])
    }

    func testJellyStretchesUntilTheNextThing() {
        var state = PlannerState()
        state.settings.dinner = .none
        state.events = [PlannerEvent(id: "party", title: "Party", day: day(10, 17), start: 600, end: 900, minStay: 60, travel: 15)]
        let plan = engine(state).planDay(day(10, 17)) // Saturday, no work
        let party = plan.live.first
        XCTAssertEqual(party?.coreStart, 585)
        XCTAssertEqual(party?.leave, 900)
        XCTAssertEqual(party?.squeezed, false)
    }

    func testOverfullDaySqueezesTasksThenPushesBedtime() {
        var state = PlannerState()
        state.tasks = (1...40).map { makeTask("Task \($0)", tier: 1, estimate: 60) }
        let plan = engine(state).planDay(day(10, 17)) // Saturday
        XCTAssertEqual(plan.level, 2)
        XCTAssertTrue(plan.items.allSatisfy(\.squished))
        // 23 half-hour pieces before dinner, 13 after, then one 15-minute
        // piece; the last 4 don't fully fit.
        XCTAssertEqual(plan.items.count, 37)
        XCTAssertEqual(plan.ghosts.count, 4)
        XCTAssertEqual(plan.sleepStart, 1550)
        XCTAssertEqual(plan.push, 170)
        XCTAssertEqual(engine(state).complaint(push: plan.push, day: plan.day, at: plan.sleepStart).prefix(22), "This is a cry for help")
    }

    func testRecurringGoalsSpreadAcrossTheWeek() {
        var state = PlannerState()
        state.tasks = [makeTask("Guitar", .recurring, tier: 2) { $0.weekly = 150; $0.minBlock = 15; $0.maxSession = 45 }]
        let chunks = engine(state).dayChunks(day(10, 15), config: DayConfig())
        // Thursday at 7 AM: 150 minutes over 4 days left is 37.5, rounded to 40.
        XCTAssertEqual(chunks.committed.first?.minutes, 40)
        XCTAssertTrue(chunks.filler.isEmpty)
    }

    func testSkipAndMustOverrides() {
        var state = PlannerState()
        state.tasks = [makeTask("Low", tier: 4), makeTask("Skip me", tier: 1)]
        state.updateDay(day(10, 15)) { config in
            config.must = ["Low"]
            config.skip = ["Skip me"]
        }
        let chunks = engine(state).dayChunks(day(10, 15), config: state.dayConfig(day(10, 15)))
        XCTAssertEqual(chunks.committed.map(\.id), ["Low"])
        XCTAssertEqual(chunks.committed.first?.must, true)
    }
}
