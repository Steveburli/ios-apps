import XCTest
@testable import DoThisNowKit

final class BasicsTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(TimeText.duration(0), "0m")
        XCTAssertEqual(TimeText.duration(45), "45m")
        XCTAssertEqual(TimeText.duration(60), "1h")
        XCTAssertEqual(TimeText.duration(90), "1h 30m")
        XCTAssertEqual(TimeText.duration(59.6), "1h")
        XCTAssertEqual(TimeText.duration(-5), "0m")
    }

    func testAgo() {
        XCTAssertEqual(TimeText.ago(days: 1), "a day")
        XCTAssertEqual(TimeText.ago(days: 5), "5 days")
        XCTAssertEqual(TimeText.ago(days: 21), "3 weeks")
        XCTAssertEqual(TimeText.ago(days: 90), "3 months")
        XCTAssertEqual(TimeText.ago(days: 547.5), "1.5 years")
        XCTAssertEqual(TimeText.ago(days: 730), "2 years")
    }

    func testCalendarDay() throws {
        let d = day(10, 17)
        XCTAssertEqual(d.key, "2026-10-17")
        XCTAssertEqual(CalendarDay(key: "2026-10-17"), d)
        XCTAssertNil(CalendarDay(key: "nope"))
        XCTAssertEqual(d.adding(days: 15, calendar: utc), day(11, 1))
        XCTAssertEqual(d.adding(days: -17, calendar: utc), day(9, 30))
        XCTAssertEqual(day(10, 14).days(until: d, calendar: utc), 3)
        XCTAssertEqual(d.days(until: day(10, 14), calendar: utc), -3)
        XCTAssertEqual(d.weekdayIndex(calendar: utc), 6) // Saturday
        XCTAssertTrue(day(9, 30) < d)

        let data = try JSONEncoder().encode([d])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2026-10-17\"]")
        XCTAssertEqual(try JSONDecoder().decode([CalendarDay].self, from: data), [d])
    }

    func testMinuteDates() {
        let date = day(10, 17).date(atMinute: 18 * 60 + 30, calendar: utc)
        XCTAssertEqual(utc.dateComponents([.day, .hour, .minute], from: date), DateComponents(day: 17, hour: 18, minute: 30))
        let late = day(10, 17).date(atMinute: 1440 + 60, calendar: utc)
        XCTAssertEqual(utc.dateComponents([.day, .hour], from: late), DateComponents(day: 18, hour: 1))
        XCTAssertEqual(utc.minuteOfDay(wednesday10am), 600)
    }

    func testWeeks() {
        XCTAssertEqual(CalendarDay(utc.mondayOfWeek(containing: wednesday10am), calendar: utc), day(10, 12))
        let sunday = day(10, 18).startDate(calendar: utc)
        XCTAssertEqual(CalendarDay(utc.mondayOfWeek(containing: sunday), calendar: utc), day(10, 12))
        XCTAssertEqual(utc.daysLeftInWeek(wednesday10am), 5)
        XCTAssertEqual(utc.daysLeftInWeek(sunday), 1)
        XCTAssertEqual(utc.daysLeftInWeek(day(10, 12).startDate(calendar: utc)), 7)
    }

    func testStakesLabels() {
        XCTAssertEqual(stakesLabel(0), "Shrug")
        XCTAssertEqual(stakesLabel(5), "Annoyed")
        XCTAssertEqual(stakesLabel(8), "Really mad")
        XCTAssertEqual(stakesLabel(10), "Furious")
    }

    func testOldOrEmptyFilesStillLoad() throws {
        let empty = try JSONDecoder().decode(PlannerState.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, PlannerState())

        let partial = #"{"tasks":[{"id":"a","title":"Fold laundry"}],"settings":{"bed":1350}}"#
        let state = try JSONDecoder().decode(PlannerState.self, from: Data(partial.utf8))
        XCTAssertEqual(state.tasks.first?.title, "Fold laundry")
        XCTAssertEqual(state.tasks.first?.tier, 3)
        XCTAssertEqual(state.settings.bed, 1350)
        XCTAssertEqual(state.settings.wake, 420)
    }

    func testRoundTripWithExamples() throws {
        var state = PlannerState()
        state.loadExamples(now: wednesday10am, calendar: utc)
        XCTAssertEqual(state.tasks.count, 13)
        XCTAssertEqual(state.events.count, 2)
        XCTAssertEqual(state.log.count, 9)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(PlannerState.self, from: data)
        XCTAssertEqual(try encoder.encode(decoded), data)
        XCTAssertEqual(decoded.tasks.map(\.title), state.tasks.map(\.title))

        state.removeExamples()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertTrue(state.events.isEmpty)
        XCTAssertTrue(state.log.isEmpty)
    }

    func testPrune() {
        var state = PlannerState()
        state.log = [LogEntry(taskID: "a", at: daysAgo(200), minutes: 10), LogEntry(taskID: "a", at: daysAgo(2), minutes: 10)]
        state.updateDay(day(10, 13)) { $0.noWork = true }
        state.updateDay(day(10, 15)) { $0.noWork = true }
        state.events = [
            PlannerEvent(title: "Old", day: day(9, 1), start: 600, end: 660, minStay: 30, travel: 0),
            PlannerEvent(title: "Recent", day: day(10, 5), start: 600, end: 660, minStay: 30, travel: 0),
        ]
        state.prune(now: wednesday10am, calendar: utc)
        XCTAssertEqual(state.log.count, 1)
        XCTAssertEqual(Array(state.days.keys), ["2026-10-15"])
        XCTAssertEqual(state.events.map(\.title), ["Recent"])
    }
}
