import XCTest
@testable import DoThisNowKit

final class HeatTests: XCTestCase {
    let today = day(10, 14)

    func heat(_ task: TaskItem) -> TaskHeat {
        task.heat(today: today, calendar: utc)
    }

    func testTierSetsTheStartingHeat() {
        let top = heat(makeTask("a", tier: 1))
        let someday = heat(makeTask("b", tier: 4))
        XCTAssertGreaterThan(top.value, someday.value)
        XCTAssertFalse(top.isAngry)
        XCTAssertEqual(top.scale, 1)
    }

    func testCloserDeadlinesAreHotter() {
        let soon = heat(makeTask("a") { $0.deadline = day(10, 15) })
        let later = heat(makeTask("b") { $0.deadline = day(10, 24) })
        let far = heat(makeTask("c") { $0.deadline = day(11, 30) })
        let none = heat(makeTask("d"))
        XCTAssertGreaterThan(soon.value, later.value)
        XCTAssertGreaterThan(later.value, far.value)
        XCTAssertEqual(far.value, none.value, accuracy: 0.0001)
    }

    func testLateTasksGrowThenStop() {
        let one = heat(makeTask("a") { $0.deadline = day(10, 13) })
        XCTAssertEqual(one.daysLate, 1)
        XCTAssertEqual(one.value, 1)
        XCTAssertEqual(one.scale, 1.1, accuracy: 0.0001)
        let three = heat(makeTask("b") { $0.deadline = day(10, 11) })
        XCTAssertEqual(three.daysLate, 3)
        XCTAssertEqual(three.scale, 1.3, accuracy: 0.0001)
        let twenty = heat(makeTask("c") { $0.deadline = day(9, 24) })
        XCTAssertEqual(twenty.daysLate, 20)
        XCTAssertEqual(twenty.scale, 1.5, accuracy: 0.0001)
        XCTAssertEqual(twenty.anger, 1)
        // Due today isn't late yet.
        XCTAssertFalse(heat(makeTask("d") { $0.deadline = today }).isAngry)
    }

    func testSnoozingWarmsATaskWithNoDeadline() {
        var state = PlannerState()
        state.tasks = [makeTask("a", tier: 3)]
        let before = heat(state.task("a")!).value
        state.snooze(["a"], until: wednesday10am)
        state.snooze(["a"], until: wednesday10am)
        XCTAssertEqual(state.task("a")?.snoozes, 2)
        XCTAssertGreaterThan(heat(state.task("a")!).value, before)
        // It stops warming after five.
        for _ in 0..<10 { state.snooze(["a"], until: wednesday10am) }
        XCTAssertEqual(heat(state.task("a")!).value, 0.2 + 0.07 * 5, accuracy: 0.0001)
    }

    func testALaterDeadlineIsAFreshStart() {
        var task = makeTask("a") { $0.deadline = day(10, 20); $0.snoozes = 4 }
        task.deadline = day(10, 18)
        task.coolIfDeadlineMovedLater(from: day(10, 20))
        XCTAssertEqual(task.snoozes, 4, "moving it earlier keeps the heat")
        task.deadline = nil
        task.coolIfDeadlineMovedLater(from: day(10, 18))
        XCTAssertEqual(task.snoozes, 4, "taking the deadline off keeps the heat")
        task.deadline = day(10, 30)
        task.coolIfDeadlineMovedLater(from: nil)
        XCTAssertEqual(task.snoozes, 0)
        task.snoozes = 3
        task.deadline = day(11, 5)
        task.coolIfDeadlineMovedLater(from: day(10, 30))
        XCTAssertEqual(task.snoozes, 0)
    }

    func testRestoringCoolsItOff() {
        var state = PlannerState()
        state.tasks = [makeTask("a") { $0.snoozes = 3; $0.archived = true }]
        state.restore("a", now: wednesday10am)
        XCTAssertEqual(state.task("a")?.snoozes, 0)
    }

    func testOldSavedTasksLoadCold() throws {
        let json = #"{"id":"x","title":"Old"}"#.data(using: .utf8)!
        let task = try JSONDecoder().decode(TaskItem.self, from: json)
        XCTAssertEqual(task.snoozes, 0)
        let settings = try JSONDecoder().decode(PlannerSettings.self, from: "{}".data(using: .utf8)!)
        XCTAssertTrue(settings.taskHeat)
    }

    func testRemindersFindTheirTask() {
        var state = PlannerState()
        state.tasks = [makeTask("a") { $0.reminderID = "r1" }]
        XCTAssertEqual(state.task(for: SourceRef(.reminders, "r1"))?.id, "a")
        XCTAssertEqual(state.task(for: SourceRef(.app, "a"))?.id, "a")
        XCTAssertNil(state.task(for: SourceRef(.inbox, "a")))
    }
}
