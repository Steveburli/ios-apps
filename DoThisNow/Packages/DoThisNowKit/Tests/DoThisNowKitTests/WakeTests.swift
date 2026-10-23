import XCTest
@testable import DoThisNowKit

final class WakeTests: XCTestCase {
    /// Thursday, Oct 15 2026 at `minute`.
    private func thursday(_ minute: Double) -> Date {
        day(10, 15).date(atMinute: minute, calendar: utc)
    }

    /// Times come with a narrow no-break space before AM and PM.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    func testAWorkdayWorksBackFromWork() {
        // Work at 9:00, a 30-minute commute (a guess), a 10-minute buffer,
        // and the starter routine: shower 15, dressed 10, breakfast 20, teeth 5.
        let plan = engine(PlannerState()).wakePlan(for: day(10, 15))
        XCTAssertEqual(plan.leave, 510)
        XCTAssertEqual(plan.commute?.estimate.minutes, 30)
        XCTAssertEqual(plan.routine, 50)
        XCTAssertEqual(plan.wake, 450)
        XCTAssertEqual(plain(plan.reason), "Work starts at 9:00 AM")
        // Eight hours before 7:30 is 11:30 the night before, and in bed 15 minutes earlier.
        XCTAssertEqual(plan.asleep, -30)
        XCTAssertEqual(plan.inBed, -45)
        XCTAssertEqual(plain(formats.time(plan.day, plan.inBed)), "11:15 PM")
    }

    func testYourTimingsChangeTheWakeUpTime() {
        var state = PlannerState()
        for minutes in [8.0, 9, 10] {
            state.timings.append(Timing(title: "Shower", start: daysAgo(minutes), seconds: minutes * 60))
        }
        // The shower takes 9 minutes, not the guessed 15, so you sleep 6 minutes
        // longer, rounded down to five.
        XCTAssertEqual(engine(state).wakePlan(for: day(10, 15)).wake, 455)
    }

    func testAnEarlierEventWins() {
        var state = PlannerState()
        state.events = [PlannerEvent(title: "Dentist", day: day(10, 15), start: 480, end: 540, minStay: 45, travel: 15)]
        let plan = engine(state).wakePlan(for: day(10, 15))
        XCTAssertEqual(plan.leave, 465)
        XCTAssertNil(plan.commute)
        XCTAssertEqual(plan.wake, 405)
        XCTAssertEqual(plain(plan.reason), "Leave for Dentist at 7:45 AM")
    }

    func testEveningEventsDontChangeTheMorning() {
        var state = PlannerState()
        state.events = [
            PlannerEvent(title: "Book club", day: day(10, 15), start: 1170, end: 1260, minStay: 60, travel: 10),
            PlannerEvent(title: "Game night", day: day(10, 17), start: 1140, end: 1260, minStay: 60, travel: 10),
        ]
        XCTAssertEqual(engine(state).wakePlan(for: day(10, 15)).leave, 510)
        let saturday = engine(state).wakePlan(for: day(10, 17))
        XCTAssertNil(saturday.leave)
        XCTAssertEqual(saturday.wake, 420)
    }

    func testADayOffUsesYourUsualWakeUpTime() {
        let plan = engine(PlannerState()).wakePlan(for: day(10, 17)) // Saturday
        XCTAssertNil(plan.leave)
        XCTAssertEqual(plan.wake, 420)
    }

    func testWhichMorning() {
        XCTAssertEqual(engine(PlannerState(), now: thursday(400)).wakeMorning(), day(10, 15))
        XCTAssertEqual(engine(PlannerState(), now: thursday(460)).wakeMorning(), day(10, 16))
    }

    func testTheAlarmFollowsThePlan() {
        var state = PlannerState()
        state.wake.alarm.on = true
        state.wake.alarm.days = Array(0...6)
        let fires = engine(state).alarmFires()
        // Wednesday's 7:30 has passed, so Thursday through Tuesday.
        XCTAssertEqual(fires.count, 6)
        XCTAssertEqual(fires.first?.date, thursday(450))
        XCTAssertEqual(fires.first?.backup, 0)
        // Saturday has no work: your usual 7:00.
        XCTAssertEqual(fires.first { $0.morning == day(10, 17) }?.date, day(10, 17).date(atMinute: 420, calendar: utc))

        state.wake.alarm.followPlan = false
        state.wake.alarm.time = 6 * 60
        XCTAssertEqual(engine(state).alarmFires().first?.date, thursday(360))
    }

    func testScanningAddsBackupsToTheNextMorningOnly() {
        var state = PlannerState()
        state.wake.alarm.on = true
        state.wake.alarm.days = Array(0...6)
        state.wake.alarm.codes = [WakeCode(name: "Toothpaste", payload: "0123")]
        var fires = engine(state).alarmFires()
        XCTAssertEqual(fires.filter { $0.morning == day(10, 15) }.count, 11)
        XCTAssertEqual(fires.filter { $0.morning == day(10, 15) }.last?.date, thursday(470))
        XCTAssertEqual(fires.count, 16)

        // Once Thursday's scan is done, Friday gets the backups.
        state.wake.alarm.stoppedOn = day(10, 15)
        fires = engine(state).alarmFires()
        XCTAssertFalse(fires.contains { $0.morning == day(10, 15) })
        XCTAssertEqual(fires.filter { $0.morning == day(10, 16) }.count, 11)

        // Partway through the backups, only the ones still to come are left.
        state.wake.alarm.stoppedOn = nil
        fires = engine(state, now: thursday(455)).alarmFires()
        XCTAssertEqual(fires.filter { $0.morning == day(10, 15) }.map(\.backup), [3, 4, 5, 6, 7, 8, 9, 10])
    }

    func testRingingUntilYouScan() {
        var state = PlannerState()
        state.wake.alarm.on = true
        XCTAssertNil(engine(state, now: thursday(455)).ringingAlarm(), "No code to scan yet")

        state.wake.alarm.codes = [WakeCode(name: "Toothpaste", payload: "0123")]
        XCTAssertNil(engine(state, now: thursday(445)).ringingAlarm())
        XCTAssertEqual(engine(state, now: thursday(455)).ringingAlarm(), day(10, 15))
        XCTAssertNil(engine(state, now: thursday(500)).ringingAlarm())

        state.wake.alarm.stoppedOn = day(10, 15)
        XCTAssertNil(engine(state, now: thursday(455)).ringingAlarm())
    }
}
