import XCTest
@testable import OMMKit

/// The daily sunlight goal, its timer, credits and reminders.
final class SunlightTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-13 at the given UTC time.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 13) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testCreditsByKind() {
        XCTAssertEqual(SunlightEntry(start: at(9), minutes: 20, kind: .openSky).creditedMinutes, 20)
        XCTAssertEqual(SunlightEntry(start: at(9), minutes: 20, kind: .shade).creditedMinutes, 10)
        XCTAssertEqual(SunlightEntry(start: at(9), minutes: 20, kind: .behindGlass).creditedMinutes, 5)
    }

    func testTimerLogsAnEntry() {
        var log = SunlightLog()
        log.startOutside(at: at(9))
        XCTAssertTrue(log.isOutside)
        XCTAssertEqual(log.minutesToday(now: at(9, 12), calendar: utc), 12)
        let entry = log.stopOutside(at: at(9, 20), kind: .shade)
        XCTAssertEqual(entry?.minutes, 20)
        XCTAssertFalse(log.isOutside)
        XCTAssertEqual(log.minutes(on: at(12), calendar: utc), 10)
    }

    func testTimerUnderAMinuteLogsNothingAndLongTimersAreCapped() {
        var log = SunlightLog()
        log.startOutside(at: at(9))
        XCTAssertNil(log.stopOutside(at: at(9).addingTimeInterval(40), kind: .openSky))
        XCTAssertTrue(log.entries.isEmpty)
        log.startOutside(at: at(1))
        XCTAssertEqual(log.stopOutside(at: at(23), kind: .openSky)?.minutes, SunlightLog.maxEntryMinutes)
    }

    func testStopCanOverrideTheMinutes() {
        var log = SunlightLog()
        log.startOutside(at: at(9))
        XCTAssertEqual(log.stopOutside(at: at(11), kind: .openSky, minutes: 25)?.minutes, 25)
    }

    func testRecentDaysAndStreak() {
        var log = SunlightLog(goalMinutes: 30)
        log.add(minutes: 30, kind: .openSky, endingAt: at(10, day: 10))
        log.add(minutes: 40, kind: .openSky, endingAt: at(10, day: 11))
        log.add(minutes: 60, kind: .shade, endingAt: at(10, day: 12))
        log.add(minutes: 10, kind: .openSky, endingAt: at(10, day: 13))
        let days = log.recentDays(7, now: at(15), calendar: utc).map(\.minutes)
        XCTAssertEqual(days, [0, 0, 0, 30, 40, 30, 10])
        // Today isn't met yet, so the streak counts back from yesterday.
        XCTAssertEqual(log.streak(now: at(15), calendar: utc), 3)
        log.add(minutes: 20, kind: .openSky, endingAt: at(16))
        XCTAssertEqual(log.streak(now: at(17), calendar: utc), 4)
    }

    func testGoalIsClamped() {
        var log = SunlightLog()
        XCTAssertEqual(log.goalMinutes, 30)
        log.setGoal(500)
        XCTAssertEqual(log.goalMinutes, SunlightLog.goalRange.upperBound)
        log.setGoal(0)
        XCTAssertEqual(log.goalMinutes, SunlightLog.goalRange.lowerBound)
    }

    func testPruneDropsOldEntries() {
        var log = SunlightLog()
        log.add(minutes: 10, kind: .openSky, endingAt: at(10).addingTimeInterval(-90 * 86_400))
        log.add(minutes: 10, kind: .openSky, endingAt: at(10))
        log.prune(now: at(12), calendar: utc)
        XCTAssertEqual(log.entries.count, 1)
    }

    func testDecodesAnOlderSave() throws {
        let json = Data(#"{"goalMinutes": 45}"#.utf8)
        let log = try JSONDecoder().decode(SunlightLog.self, from: json)
        XCTAssertEqual(log.goalMinutes, 45)
        XCTAssertEqual(log.midday, TimeOfDay(hour: 12, minute: 30))
        XCTAssertFalse(log.remindersOn)
    }

    func testNoRemindersWhenOff() {
        XCTAssertTrue(SunlightReminders.plan(for: SunlightLog(), now: at(7), calendar: utc).isEmpty)
    }

    func testRemindersForAFreshDay() {
        let log = SunlightLog(remindersOn: true)
        let plan = SunlightReminders.plan(for: log, now: at(7), calendar: utc)
        XCTAssertEqual(plan.count, 3 * SunlightReminders.daysAhead)
        XCTAssertEqual(plan.prefix(3).map(\.kind), [.morning, .midday, .lastCall])
        XCTAssertEqual(plan.first?.date, at(8))
        XCTAssertEqual(plan.first?.id, "sunlight-morning-2026-11-13")
    }

    func testMiddayIsSkippedOnceHalfwayAndAllOnceMet() {
        var log = SunlightLog(goalMinutes: 30, remindersOn: true)
        log.add(minutes: 15, kind: .openSky, endingAt: at(9))
        var today = SunlightReminders.plan(for: log, now: at(10), calendar: utc).filter { utc.isDate($0.date, inSameDayAs: at(10)) }
        XCTAssertEqual(today.map(\.kind), [.lastCall])
        XCTAssertTrue(today[0].body.contains("15 min"))
        log.add(minutes: 15, kind: .openSky, endingAt: at(11))
        today = SunlightReminders.plan(for: log, now: at(11), calendar: utc).filter { utc.isDate($0.date, inSameDayAs: at(11)) }
        XCTAssertTrue(today.isEmpty)
    }

    func testNoRemindersTodayWhileOutside() {
        var log = SunlightLog(remindersOn: true)
        log.startOutside(at: at(12))
        let plan = SunlightReminders.plan(for: log, now: at(12, 10), calendar: utc)
        XCTAssertFalse(plan.contains { utc.isDate($0.date, inSameDayAs: at(12)) })
        XCTAssertEqual(plan.count, 3 * (SunlightReminders.daysAhead - 1))
    }
}
