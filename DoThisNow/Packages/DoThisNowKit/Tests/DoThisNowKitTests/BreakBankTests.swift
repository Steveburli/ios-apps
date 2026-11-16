import XCTest
@testable import DoThisNowKit

final class BreakBankTests: XCTestCase {
    private let start = wednesday10am

    private func minutes(_ m: Double) -> TimeInterval { m * 60 }

    func testFocusEarnsOneMinutePerFiveByDefault() {
        var state = PlannerState()
        state.startFocus(at: start, calendar: utc)
        XCTAssertEqual(state.breakBalance(at: start.addingTimeInterval(minutes(25)), calendar: utc), minutes(5), accuracy: 0.001)
        let earned = state.stopFocus(at: start.addingTimeInterval(minutes(60)), calendar: utc)
        XCTAssertEqual(earned ?? 0, minutes(12), accuracy: 0.001)
        XCTAssertEqual(state.breakMinutesAvailable(at: start.addingTimeInterval(minutes(60)), calendar: utc), 12)
        XCTAssertEqual(state.timings.last?.title, "Focus")
    }

    func testRatioFollowsSettings() {
        var state = PlannerState()
        state.settings.workPerBreak = 3
        state.startFocus(at: start, calendar: utc)
        state.stopFocus(at: start.addingTimeInterval(minutes(30)), calendar: utc)
        XCTAssertEqual(state.breaks.seconds, minutes(10), accuracy: 0.001)
    }

    func testForgottenTimerStopsCountingAfterNinetyMinutes() {
        var state = PlannerState()
        state.startFocus(at: start, calendar: utc)
        let later = start.addingTimeInterval(minutes(200))
        XCTAssertTrue(state.needsStillWorking(at: later))
        XCTAssertEqual(state.focusWork(at: later), minutes(90), accuracy: 0.001)
        state.confirmStillWorking(at: later)
        XCTAssertFalse(state.needsStillWorking(at: later))
        XCTAssertEqual(state.focusWork(at: later.addingTimeInterval(minutes(10))), minutes(210), accuracy: 0.001)
    }

    func testBreakSpendsOnlyTimeTaken() {
        var state = PlannerState()
        state.breaks.day = CalendarDay(start, calendar: utc)
        state.breaks.seconds = minutes(20)
        state.startBreak(minutes: 15, at: start, calendar: utc)
        XCTAssertEqual(state.breakBalance(at: start.addingTimeInterval(minutes(5)), calendar: utc), minutes(15), accuracy: 0.001)
        state.endBreak(at: start.addingTimeInterval(minutes(5)), calendar: utc)
        XCTAssertNil(state.breaks.current)
        XCTAssertEqual(state.breaks.seconds, minutes(15), accuracy: 0.001)
    }

    func testBreakStopsSpendingWhenOver() {
        var state = PlannerState()
        state.startBreak(minutes: 10, at: start, calendar: utc)
        state.endBreak(at: start.addingTimeInterval(minutes(45)), calendar: utc)
        XCTAssertEqual(state.breaks.seconds, -minutes(10), accuracy: 0.001)
    }

    func testDebtIsPaidBackByWork() {
        var state = PlannerState()
        state.startBreak(minutes: 10, at: start, calendar: utc)
        // Starting focus ends the break.
        state.startFocus(at: start.addingTimeInterval(minutes(10)), calendar: utc)
        XCTAssertNil(state.breaks.current)
        XCTAssertEqual(state.breaks.seconds, -minutes(10), accuracy: 0.001)
        state.stopFocus(at: start.addingTimeInterval(minutes(35)), calendar: utc)
        XCTAssertEqual(state.breaks.seconds, -minutes(5), accuracy: 0.001)
        XCTAssertEqual(state.breakMinutesAvailable(at: start.addingTimeInterval(minutes(35)), calendar: utc), 0)
    }

    func testNewDayStartsAtZeroButDebtCarries() {
        var state = PlannerState()
        state.earnBreak(forWork: minutes(100), at: start, calendar: utc)
        XCTAssertEqual(state.breaks.seconds, minutes(20), accuracy: 0.001)
        let tomorrow = start.addingTimeInterval(86_400)
        XCTAssertEqual(state.breakBalance(at: tomorrow, calendar: utc), 0)
        state.earnBreak(forWork: minutes(5), at: tomorrow, calendar: utc)
        XCTAssertEqual(state.breaks.seconds, minutes(1), accuracy: 0.001)

        var owing = PlannerState()
        owing.breaks.day = CalendarDay(start, calendar: utc)
        owing.breaks.seconds = -minutes(8)
        XCTAssertEqual(owing.breakBalance(at: tomorrow, calendar: utc), -minutes(8), accuracy: 0.001)
    }

    func testSessionsDontDoubleCountWithFocusOrBreak() {
        var state = PlannerState()
        state.startFocus(at: start, calendar: utc)
        XCTAssertEqual(state.earnBreak(forWork: minutes(30), at: start, calendar: utc), 0)
        state.startBreak(minutes: 5, at: start.addingTimeInterval(minutes(5)), calendar: utc)
        XCTAssertNil(state.breaks.focus)
        XCTAssertEqual(state.earnBreak(forWork: minutes(30), at: start, calendar: utc), 0)
    }

    func testBreakFitsUseTrackTimings() {
        var state = PlannerState()
        state.breaks.ideas = [
            BreakIdea(name: "Workout", minutes: 15),
            BreakIdea(name: "Meditate", minutes: 10),
            BreakIdea(name: "Long walk", minutes: 45),
        ]
        state.timings = [Timing(title: "Workout", start: start, seconds: minutes(20))]
        let fits = state.breakFits(minutes: 40)
        XCTAssertEqual(fits.map(\.idea.name), ["Workout", "Meditate"])
        XCTAssertEqual(fits.first?.minutes, 20)
        XCTAssertEqual(fits.first?.times, 2)
        XCTAssertEqual(fits.last?.times, 4)
    }

    func testOldFilesLoadWithStarterIdeas() throws {
        let state = try JSONDecoder().decode(PlannerState.self, from: Data("{}".utf8))
        XCTAssertEqual(state.breaks.ideas, BreakIdea.starters)
        XCTAssertEqual(state.settings.workPerBreak, 5)
    }
}
