import XCTest
@testable import OMMKit

/// The home grid's automatic picks: one muscle per body group, rotating
/// muscle groups, least recently trained first, crossed-out muscles skipped.
final class NextGroupsTests: XCTestCase {
    private func keys(_ state: ProgramState) -> [String] {
        NextGroups.picks(in: state).map(\.key)
    }

    /// Runs one full workout of the current picks, a day apart.
    private func train(_ state: inout ProgramState, day: Int) {
        let picked = keys(state)
        state.recordWorkout(groupKeys: picked, setsPerGroup: WorkoutPlan.setsPerGroup, dayKey: "d\(day)")
        state.markTrained(groupKeys: picked, at: Date(timeIntervalSince1970: Double(day) * 86_400))
    }

    func testFreshProgramStartsWithMidQuadsRectus() {
        XCTAssertEqual(keys(ProgramState()), ["Mid", "Quads", "Rectus"])
    }

    func testRotatesMuscleGroupsEachWorkout() {
        var state = ProgramState()
        var seen: [[String]] = []
        for day in 1...5 {
            seen.append(keys(state))
            train(&state, day: day)
        }
        // Upper: Chest, Back, Shoulders, Arms, then back to Chest.
        XCTAssertEqual(seen.map { $0[0] }, ["Mid", "Traps", "Front", "Biceps", "Upper"])
        // Lower: Thighs and Calves take turns; Quads needs two workouts.
        XCTAssertEqual(seen.map { $0[1] }, ["Quads", "Standing", "Quads", "Standing", "Hams"])
        // Core has one muscle group, so Rectus runs until it's crossed out.
        XCTAssertEqual(seen.map { $0[2] }, ["Rectus", "Rectus", "Rectus", "Rectus", "Transversal"])
    }

    func testSkipsCrossedOutMusclesAndFinishedRows() {
        var state = ProgramState()
        for key in ["Rectus", "Transversal", "Oblique", "Lower Abs"] {
            state.progress[key] = 12
        }
        state.progress["Mid"] = 3
        let picks = keys(state)
        XCTAssertEqual(picks.count, 2)
        XCTAssertEqual(picks[0], "Upper")
    }

    func testFinishesAStartedMuscleFirst() {
        var state = ProgramState()
        state.progress["Hams"] = 3
        XCTAssertEqual(NextGroups.pick(.lower, in: state)?.key, "Hams")
    }

    func testFillKeepsManualPicks() {
        var selection = GroupSelection()
        selection.toggle(Catalog.group("Lats")!)
        selection.fillSuggested(from: ProgramState())
        XCTAssertEqual(selection.orderedKeys, ["Lats", "Quads", "Rectus"])
    }
}
