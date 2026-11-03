import XCTest
@testable import OMMKit

/// Rest timer math with cardio, the grid's sections and fade, weight
/// suggestions, cardio limits and stretch routines.
final class VersionTwoTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func group(_ key: String) -> MuscleGroup {
        Catalog.group(key)!
    }

    // MARK: Grid sections

    func testSectionsAreUpperLowerCore() {
        XCTAssertEqual(Catalog.sections.map(\.category), [.upper, .lower, .core])
        XCTAssertEqual(Catalog.sections[0].rows.map(\.area), ["Chest", "Back", "Shoulders", "Arms"])
        XCTAssertEqual(Catalog.sections[1].rows.map(\.area), ["Thighs", "Calves"])
        XCTAssertEqual(Catalog.sections[2].rows.map(\.area), ["Core"])
        XCTAssertEqual(Catalog.areas.count, 7)
    }

    // MARK: Fade

    func testFreshnessFadesOverSevenDays() {
        let trained = utc.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 18))!
        var state = ProgramState()
        XCTAssertEqual(state.freshness(of: group("Mid"), now: trained, calendar: utc), 0)
        XCTAssertNil(state.daysSinceTrained(group("Mid"), now: trained, calendar: utc))

        state.markTrained(groupKeys: ["Mid"], at: trained)
        func days(_ n: Double) -> Date { trained.addingTimeInterval(n * 86_400) }
        XCTAssertEqual(state.freshness(of: group("Mid"), now: days(0), calendar: utc), 1)
        XCTAssertEqual(state.daysSinceTrained(group("Mid"), now: days(1), calendar: utc), 1)
        XCTAssertEqual(state.freshness(of: group("Mid"), now: days(1), calendar: utc), 6.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(state.freshness(of: group("Mid"), now: days(7), calendar: utc), 0)
        XCTAssertEqual(state.freshness(of: group("Mid"), now: days(30), calendar: utc), 0)
    }

    func testOldSavesStillLoad() throws {
        let old = #"{"progress":{"Mid":3},"weights":{"Mid|Dips":"20"},"dailySets":{"2026-10-21":9}}"#
        let state = try JSONDecoder().decode(ProgramState.self, from: Data(old.utf8))
        XCTAssertEqual(state.progress["Mid"], 3)
        XCTAssertEqual(state.weights["Mid|Dips"], "20")
        XCTAssertTrue(state.lastTrained.isEmpty)
        XCTAssertTrue(state.lifts.isEmpty)

        var updated = state
        updated.markTrained(groupKeys: ["Mid"], at: Date(timeIntervalSince1970: 1_000_000))
        updated.logLift(forKey: "Mid|Dips", weight: "20", reps: [12, 10, 9], tooHeavy: false)
        let round = try JSONDecoder().decode(ProgramState.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(round, updated)
    }

    // MARK: Weight suggestions

    func testGoUpWhenFirstSetHitsTwelveAndLastHitsNine() {
        XCTAssertEqual(WeightAdvice(log: LiftLog(weight: "35", reps: [12, 11, 10]))?.direction, .up)
        XCTAssertEqual(WeightAdvice(log: LiftLog(weight: "35", reps: [12, 11, 10]))?.weightText, "40")
        XCTAssertEqual(WeightAdvice(log: LiftLog(weight: "35", reps: [12, 8, 9]))?.direction, .up)
        XCTAssertEqual(WeightAdvice(log: LiftLog(weight: "35", reps: [12, 12, 12]))?.direction, .up)
    }

    func testStayWhenRepsDropOff() {
        let advice = WeightAdvice(log: LiftLog(weight: "35", reps: [12, 10, 8]))
        XCTAssertEqual(advice?.direction, .same)
        XCTAssertEqual(advice?.weightText, "35")
        XCTAssertEqual(WeightAdvice(log: LiftLog(weight: "35", reps: [11, 11, 11]))?.direction, .same)
    }

    func testTooHeavyGoesDownFiveEvenWithTwelves() {
        let advice = WeightAdvice(log: LiftLog(weight: "35", reps: [12, 12, 12], tooHeavy: true))
        XCTAssertEqual(advice?.direction, .down)
        XCTAssertEqual(advice?.weightText, "30")
        XCTAssertEqual(WeightAdvice(log: LiftLog(weight: "3", reps: [], tooHeavy: true))?.weightText, "0")
    }

    func testNoAdviceWithoutRepsOrANumber() {
        XCTAssertNil(WeightAdvice(log: LiftLog(weight: "35", reps: [])))
        XCTAssertNil(WeightAdvice(log: LiftLog(weight: "red band", reps: [12, 12, 12])))
        XCTAssertEqual(WeightAdvice(log: LiftLog(weight: "37.5", reps: [12, 10, 9]))?.weightText, "42.5")
    }

    func testLoggingLifts() {
        var state = ProgramState()
        state.logLift(forKey: "k", weight: "35", reps: [12, 10, 9], tooHeavy: false)
        XCTAssertEqual(state.lifts["k"], LiftLog(weight: "35", reps: [12, 10, 9]))

        // Skipped this time, same weight still in the box: keep the log.
        state.logLift(forKey: "k", weight: "35", reps: [], tooHeavy: false)
        XCTAssertNotNil(state.lifts["k"])

        // Weight changed with no reps: the old reps no longer apply.
        state.logLift(forKey: "k", weight: "40", reps: [], tooHeavy: false)
        XCTAssertNil(state.lifts["k"])

        state.logLift(forKey: "k", weight: "40", reps: [], tooHeavy: true)
        XCTAssertEqual(state.lifts["k"], LiftLog(weight: "40", reps: [], tooHeavy: true))

        state.logLift(forKey: "k", weight: " ", reps: [10], tooHeavy: false)
        XCTAssertNil(state.lifts["k"])
    }

    // MARK: Cardio

    func testCardioComesOutOfTheTotal() {
        let keys = ["Mid", "Quads", "Rectus"]
        // 27 minutes with 9 of cardio leaves 18 for 9 sets: 120 s each, so 90 s rest.
        let plan = WorkoutPlan(groupKeys: keys, durationMinutes: 27, cardioMinutes: 9)
        XCTAssertEqual(plan.cardioMinutes, 9)
        XCTAssertEqual(plan.restSeconds, 90)
        XCTAssertEqual(WorkoutPlan(groupKeys: keys, durationMinutes: 27).restSeconds, 150)
        XCTAssertEqual(WorkoutPlan(groupKeys: keys, durationMinutes: 27).cardioMinutes, 0)
    }

    func testCardioLimits() {
        XCTAssertEqual(Cardio.maxMinutes(forDuration: 9), 3)
        XCTAssertEqual(Cardio.maxMinutes(forDuration: 27), 21)
        XCTAssertEqual(Cardio.maxMinutes(forDuration: 90), 30)
        XCTAssertEqual(Cardio.clamp(21, forDuration: 15), 9)
        XCTAssertEqual(Cardio.clamp(0, forDuration: 60), 3)
    }

    func testSetsAfterAndAreas() {
        let plan = WorkoutPlan(groupKeys: ["Front", "Hams", "Oblique"], durationMinutes: 27)
        XCTAssertEqual(plan.setsAfter(0), 8)
        XCTAssertEqual(plan.setsAfter(8), 0)
        XCTAssertEqual(plan.areas, ["Shoulders", "Thighs", "Core"])
        XCTAssertEqual(WorkoutPlan(groupKeys: ["Mid", "Inner (Chest)"], durationMinutes: 27).areas, ["Chest"])
    }

    // MARK: Stretches

    func testEveryAreaHasStretches() {
        for area in Catalog.areas {
            XCTAssertEqual(Stretches.byArea[area]?.count, 2, area)
        }
    }

    func testRoutineSplitsEachSideStretches() {
        let core = Stretches.routine(areas: ["Core"])
        XCTAssertEqual(core.map(\.title), ["Cobra Lift", "Lying Twist, left side", "Lying Twist, right side"])
        XCTAssertEqual(Stretches.minutes(for: core), 2)

        let afterWorkout = Stretches.routine(areas: ["Shoulders", "Thighs", "Core"])
        XCTAssertEqual(afterWorkout.count, 11)
        XCTAssertEqual(Stretches.minutes(for: afterWorkout), 6)
        XCTAssertTrue(Stretches.routine(areas: []).isEmpty)
    }
}
