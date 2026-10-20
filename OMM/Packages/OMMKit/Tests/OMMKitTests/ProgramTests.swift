import XCTest
@testable import OMMKit

final class ProgramTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func group(_ key: String) -> MuscleGroup {
        Catalog.group(key)!
    }

    func testRestSecondsMatchTheWebApp() {
        let full = WorkoutPlan(groupKeys: ["Mid", "Quads", "Rectus"], durationMinutes: 27)
        XCTAssertEqual(full.steps.count, 9)
        XCTAssertEqual(full.restSeconds, 150)

        XCTAssertEqual(WorkoutPlan(groupKeys: ["Mid"], durationMinutes: 9).restSeconds, 150)
        XCTAssertEqual(WorkoutPlan(groupKeys: ["Mid", "Quads", "Rectus"], durationMinutes: 9).restSeconds, 30)
        XCTAssertEqual(WorkoutPlan(groupKeys: ["Mid"], durationMinutes: 90).restSeconds, 1770)
        // 30 minutes over 9 sets is 200 seconds.
        XCTAssertEqual(WorkoutPlan(groupKeys: ["Mid", "Quads", "Rectus"], durationMinutes: 30).restSeconds, 170)
        XCTAssertEqual(WorkoutPlan(groupKeys: [], durationMinutes: 27).restSeconds, 0)
    }

    func testStepsCycleThroughGroupsThreeTimes() {
        let plan = WorkoutPlan(groupKeys: ["Mid", "Quads"], durationMinutes: 27)
        XCTAssertEqual(plan.steps.map(\.groupKey), ["Mid", "Quads", "Mid", "Quads", "Mid", "Quads"])
        XCTAssertEqual(plan.steps.map(\.set), [1, 1, 2, 2, 3, 3])
    }

    func testSelectionKeepsOnePerCategory() {
        var selection = GroupSelection()
        selection.toggle(group("Mid"))
        selection.toggle(group("Rectus"))
        selection.toggle(group("Lats"))
        selection.toggle(group("Quads"))
        XCTAssertEqual(selection.orderedKeys, ["Lats", "Quads", "Rectus"])

        selection.toggle(group("Quads"))
        XCTAssertEqual(selection.orderedKeys, ["Lats", "Rectus"])
        XCTAssertFalse(selection.isEmpty)

        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    func testThresholds() {
        var state = ProgramState()
        state.recordWorkout(groupKeys: ["Mid", "Quads", "Rectus"], setsPerGroup: 3, dayKey: "2026-10-17")
        XCTAssertTrue(state.isDone(group("Mid")))
        XCTAssertFalse(state.isDone(group("Quads")))
        XCTAssertFalse(state.isDone(group("Rectus")))

        state.recordWorkout(groupKeys: ["Quads", "Rectus"], setsPerGroup: 3, dayKey: "2026-10-18")
        XCTAssertTrue(state.isDone(group("Quads")))
        XCTAssertFalse(state.isDone(group("Rectus")))

        state.recordWorkout(groupKeys: ["Rectus"], setsPerGroup: 3, dayKey: "2026-10-19")
        state.recordWorkout(groupKeys: ["Rectus"], setsPerGroup: 3, dayKey: "2026-10-20")
        XCTAssertTrue(state.isDone(group("Rectus")))
    }

    func testSelectionDropsFinishedGroups() {
        var state = ProgramState()
        var selection = GroupSelection()
        selection.toggle(group("Mid"))
        selection.toggle(group("Quads"))
        state.recordWorkout(groupKeys: ["Mid"], setsPerGroup: 3, dayKey: "2026-10-17")
        selection.removeCompleted(in: state)
        XCTAssertEqual(selection.orderedKeys, ["Quads"])
    }

    func testEstimate() {
        var state = ProgramState()
        XCTAssertEqual(state.remainingSets, 144)
        XCTAssertNil(state.estimatedDaysRemaining)

        state.recordWorkout(groupKeys: ["Mid", "Quads", "Rectus"], setsPerGroup: 3, dayKey: "2026-10-17")
        XCTAssertEqual(state.dailySets["2026-10-17"], 9)
        XCTAssertEqual(state.remainingSets, 135)
        XCTAssertEqual(state.estimatedDaysRemaining, 15)

        // A second, smaller workout the same day adds to that day.
        state.recordWorkout(groupKeys: ["Lats"], setsPerGroup: 3, dayKey: "2026-10-17")
        XCTAssertEqual(state.dailySets["2026-10-17"], 12)
        XCTAssertEqual(state.remainingSets, 132)
        XCTAssertEqual(state.estimatedDaysRemaining, 11)

        // 129 left at (12 + 3) / 2 = 7.5 a day is 17.2, rounded up to 18.
        state.recordWorkout(groupKeys: ["Traps"], setsPerGroup: 3, dayKey: "2026-10-18")
        XCTAssertEqual(state.remainingSets, 129)
        XCTAssertEqual(state.estimatedDaysRemaining, 18)
    }

    func testCompletion() {
        var state = ProgramState()
        for group in Catalog.groups {
            state.progress[group.key] = group.category.threshold
        }
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.estimatedDaysRemaining, 0)
    }

    func testOverflowDoesNotCountTwice() {
        var state = ProgramState()
        state.progress["Mid"] = 9
        XCTAssertEqual(state.remainingSets, 141)
    }

    func testWeights() {
        var state = ProgramState()
        let mid = group("Mid")
        let key = ProgramState.weightKey(group: mid, exercise: "Flat Dumbbell Press")
        XCTAssertEqual(key, "Mid|Flat Dumbbell Press")

        state.setWeight(" 135 ", forKey: key)
        XCTAssertEqual(state.weight(for: mid, exercise: "Flat Dumbbell Press"), "135")

        state.setWeight("", forKey: key)
        XCTAssertNil(state.weight(for: mid, exercise: "Flat Dumbbell Press"))
    }

    func testStartDateIsSetOnce() {
        var state = ProgramState()
        let first = Date(timeIntervalSince1970: 1_790_000_000)
        state.markStarted(at: first)
        state.markStarted(at: first.addingTimeInterval(86_400))
        XCTAssertEqual(state.startDate, first)
    }

    func testCodableRoundTrip() throws {
        var state = ProgramState()
        state.markStarted(at: Date(timeIntervalSince1970: 1_790_000_000))
        state.recordWorkout(groupKeys: ["Mid", "Quads"], setsPerGroup: 3, dayKey: "2026-10-17")
        state.setWeight("40", forKey: "Quads|Leg Press")
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(ProgramState.self, from: data), state)
    }

    func testDayKeyAndDayCount() {
        let calendar = utc
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23))!
        XCTAssertEqual(DayKey.string(for: start, calendar: calendar), "2026-10-17")

        XCTAssertEqual(DayKey.daysInclusive(from: start, to: start, calendar: calendar), 1)
        let nextMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 1))!
        XCTAssertEqual(DayKey.daysInclusive(from: start, to: nextMorning, calendar: calendar), 2)
        let later = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 8))!
        XCTAssertEqual(DayKey.daysInclusive(from: start, to: later, calendar: calendar), 31)
    }
}
