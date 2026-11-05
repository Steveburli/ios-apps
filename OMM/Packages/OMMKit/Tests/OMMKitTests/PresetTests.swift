import XCTest
@testable import OMMKit

/// One-tap preset workouts and the group guesses that fill them in.
final class PresetTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A machine circuit like the one at Steve's gym, filled in from guesses.
    private let circuitNames = ["Chest Press", "Seated Row", "Leg Curl", "Leg Extension", "Shoulder Press",
                                "Lat Pulldown", "Back Extension", "Abdominal Crunch", "Triceps",
                                "Biceps Curl", "Leg Press"]

    private func guessedCircuit() -> Preset {
        Preset(name: "Machine Circuit",
               exercises: circuitNames.map { .init(name: $0, groupKey: GroupGuess.group(for: $0)?.key) })
    }

    func testGuessesForCommonMachines() {
        let guesses = circuitNames.map { GroupGuess.group(for: $0)?.key }
        XCTAssertEqual(guesses, ["Mid", "Lats", "Hams", "Quads", "Front", "Lats", "Lower Back",
                                 "Rectus", "Triceps", "Biceps", "Quads"])
        XCTAssertEqual(GroupGuess.group(for: "Calf Raise")?.key, "Standing")
        XCTAssertEqual(GroupGuess.group(for: "Incline Chest Press")?.key, "Upper")
        XCTAssertEqual(GroupGuess.group(for: "Lateral Raise")?.key, "Lateral")
        XCTAssertEqual(GroupGuess.group(for: "Hip Abductor")?.key, "Outer")
        XCTAssertEqual(GroupGuess.group(for: "Wrist Curl")?.key, "Forearm")
        XCTAssertNil(GroupGuess.group(for: "Machine 7"))
    }

    func testSetsByGroupFollowsTheGrid() {
        let circuit = guessedCircuit()
        XCTAssertTrue(circuit.isReady)
        XCTAssertEqual(circuit.totalSets, 11)
        let summary = circuit.setsByGroup.map { "\($0.group.key) \($0.sets)" }
        XCTAssertEqual(summary, ["Mid 1", "Lats 2", "Lower Back 1", "Front 1", "Biceps 1", "Triceps 1",
                                 "Quads 2", "Hams 1", "Rectus 1"])
    }

    func testNotReadyWithoutNameOrGroups() {
        XCTAssertFalse(Preset(name: "", exercises: [.init(name: "Row", groupKey: "Lats")]).isReady)
        XCTAssertFalse(Preset(name: "Circuit", exercises: []).isReady)
        XCTAssertFalse(Preset(name: "Circuit", exercises: [.init(name: "Machine 7")]).isReady)
    }

    func testRecordingAPreset() {
        let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        var state = ProgramState()
        state.progress["Mid"] = 3      // already crossed off
        state.progress["Lats"] = 2     // one set from done

        let counted = state.recordPreset(guessedCircuit(), at: now, calendar: utc)

        XCTAssertEqual(state.progress["Mid"], 4)
        XCTAssertEqual(state.progress["Lats"], 4)
        XCTAssertEqual(state.progress["Quads"], 2)
        XCTAssertEqual(state.progress["Rectus"], 1)
        // 11 sets, minus 1 on finished Mid, minus 1 of Lats' 2 past its threshold.
        XCTAssertEqual(counted, 9)
        XCTAssertEqual(state.dailySets["2026-11-05"], 9)
        XCTAssertEqual(state.startDate, now)
        XCTAssertEqual(state.daysSinceTrained(Catalog.group("Hams")!, now: now, calendar: utc), 0)
        XCTAssertTrue(state.isDone(Catalog.group("Lats")!))
    }

    func testPresetsSaveAndLoad() throws {
        let presets = [guessedCircuit()]
        let round = try JSONDecoder().decode([Preset].self, from: JSONEncoder().encode(presets))
        XCTAssertEqual(round, presets)
    }
}
