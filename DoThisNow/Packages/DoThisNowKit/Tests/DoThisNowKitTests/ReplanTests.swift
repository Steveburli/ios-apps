import XCTest
@testable import DoThisNowKit

final class ReplanTests: XCTestCase {
    private func block(_ id: String, _ start: Int, _ minutes: Int, on date: CalendarDay = day(10, 14),
                       source: TaskSource = .inbox) -> TimeBlock {
        TimeBlock(id: id, ref: SourceRef(source, id), title: id, day: date, start: start, minutes: minutes)
    }

    /// No work, no dinner, so only the blocks shape the day. It's 10:00 on Wednesday the 14th.
    private func emptyDay() -> PlannerState {
        var state = PlannerState()
        state.settings.work.on = false
        state.settings.dinner = .none
        return state
    }

    func testMissedBlocksAreTheOnesThatEndedUndone() {
        var state = emptyDay()
        var finished = block("finished", 420, 30)
        finished.done = true
        state.blocks = [block("late", 540, 30), block("early", 480, 30), finished, block("now", 590, 30),
                        block("yesterday", 480, 30, on: day(10, 13))]
        XCTAssertEqual(engine(state).missedBlocks.map(\.id), ["early", "late"])
    }

    func testTheBlockYoureDoingIsntMissed() {
        var state = emptyDay()
        state.blocks = [block("early", 480, 30)]
        state.active = ActiveSession(taskIDs: [], title: "early", planned: 30, startedAt: daysAgo(0.1), bundle: false)
        state.active?.blockID = "early"
        XCTAssertTrue(engine(state).missedBlocks.isEmpty)
    }

    func testMissedBlocksGoInTheGapsLaterToday() {
        var state = emptyDay()
        state.blocks = [block("a", 480, 60), block("b", 540, 30), block("c", 600, 60)]
        let replan = engine(state).replan()
        XCTAssertEqual(replan.moves.map(\.id), ["a", "b"])
        XCTAssertEqual(replan.moves.map(\.to), [660, 720])
        XCTAssertTrue(replan.overflow.isEmpty)
    }

    func testWhatDoesntFitTodayLooksAtTomorrow() {
        var state = emptyDay()
        state.settings.bed = 11 * 60 + 30
        state.blocks = [block("big", 480, 60), block("small", 540, 30), block("c", 600, 60)]
        let replan = engine(state).replan()
        XCTAssertEqual(replan.moves.map(\.id), ["small"])
        XCTAssertEqual(replan.moves.first?.to, 660)
        XCTAssertEqual(replan.overflow.map(\.id), ["big"])
        XCTAssertEqual(replan.overflow.first?.tomorrow, 420)
    }

    func testApplyingMovesBlocksAndHandlesLeftovers() {
        var state = emptyDay()
        state.settings.bed = 11 * 60 + 30
        state.tasks = [makeTask("chore")]
        state.blocks = [block("chore", 400, 60, source: .app), block("note", 470, 60), block("trip", 530, 60),
                        block("small", 590, 5), block("c", 600, 60)]
        let replan = engine(state).replan()
        XCTAssertEqual(replan.moves.map(\.id), ["small"])
        XCTAssertEqual(Set(replan.overflow.map(\.id)), ["chore", "note", "trip"])

        state.apply(replan, leftovers: ["chore": .letGo, "note": .inbox], today: day(10, 14), now: wednesday10am, calendar: utc)
        XCTAssertEqual(state.block("small")?.start, 660)
        XCTAssertNil(state.block("chore"))
        XCTAssertTrue(state.task("chore")?.archived == true)
        XCTAssertNil(state.block("note"))
        XCTAssertFalse(state.inbox.hidden.contains("inbox:note"))
        XCTAssertEqual(state.block("trip")?.day, day(10, 15))
        // Tomorrow's gaps go in order: chore 7:00, note 8:00, trip 9:00.
        XCTAssertEqual(state.block("trip")?.start, 540)
    }
}
