import Foundation
import OMMKit

/// The cloud build launches the app with `-screenshots <screen>` to photograph
/// each screen with sample data: home, quicklog, preset, workout, howto, weights,
/// cardio, stretch, stretchtab, routine or complete. Nothing here runs in normal use.
enum Screenshots {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool {
        screen != nil
    }

    /// Twelve days in: some groups crossed out, a few trained this week, and
    /// a few weights and reps remembered.
    static func sampleProgram(now: Date = Date()) -> ProgramState {
        func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(Double(-days) * 86_400) }
        var state = ProgramState()
        state.startDate = daysAgo(12)
        for key in ["Mid", "Upper", "Traps", "Lats", "Biceps", "Triceps", "Rear"] {
            state.progress[key] = 3
        }
        for key in ["Quads", "Standing"] {
            state.progress[key] = 6
        }
        state.progress["Hams"] = 3
        state.progress["Rectus"] = 12
        state.progress["Oblique"] = 6
        for days in [1, 3, 5, 7, 9, 12] {
            state.dailySets[DayKey.string(for: daysAgo(days))] = 9
        }
        let trained: [(String, Int)] = [("Biceps", 1), ("Standing", 1), ("Transversal", 1),
                                        ("Lats", 3), ("Hams", 3), ("Lower Abs", 3),
                                        ("Quads", 5), ("Seated", 5)]
        for (key, days) in trained {
            state.lastTrained[key] = daysAgo(days)
        }
        state.weights["Front|Dumbbell Shoulder Press"] = "35"
        state.weights["Front|Arnold Press"] = "30"
        state.weights["Front|Front Raises (Dumbbell/Plate)"] = "15"
        state.weights["Hams|Romanian Deadlift (Barbell/Dumbbell)"] = "95"
        state.weights["Hams|Kettlebell Swings"] = "35"
        state.weights["Hams|Seated Leg Curl Machine"] = "70"
        state.weights["Oblique|Dumbbell Side Bends"] = "40"
        state.lifts["Front|Dumbbell Shoulder Press"] = LiftLog(weight: "35", reps: [12, 11, 10])
        state.lifts["Hams|Romanian Deadlift (Barbell/Dumbbell)"] = LiftLog(weight: "95", reps: [12, 10, 9])
        state.lifts["Hams|Kettlebell Swings"] = LiftLog(weight: "35", reps: [12, 12, 11], tooHeavy: true)
        state.lifts["Hams|Seated Leg Curl Machine"] = LiftLog(weight: "70", reps: [12, 10, 8])
        return state
    }

    /// Two saved stretch routines.
    static func sampleRoutines() -> [StretchRoutine] {
        [
            StretchRoutine(name: "Morning Loosen-Up", items: [
                .init(stretchID: "upward-reach", holdSeconds: 20),
                .init(stretchID: "side-reach", holdSeconds: 20),
                .init(stretchID: "forward-fold", holdSeconds: 30),
                .init(stretchID: "cat-cow", holdSeconds: 45),
                .init(stretchID: "low-lunge", holdSeconds: 30),
                .init(stretchID: "childs-pose", holdSeconds: 60),
            ]),
            StretchRoutine(name: "Desk Neck and Shoulders", items: [
                .init(stretchID: "neck-tilt", holdSeconds: 30),
                .init(stretchID: "cross-arm", holdSeconds: 30),
                .init(stretchID: "eagle-arms", holdSeconds: 20),
                .init(stretchID: "doorway-opener", holdSeconds: 45),
            ]),
        ]
    }

    /// A machine circuit and a short core routine, groups filled in by guess.
    static func samplePresets() -> [Preset] {
        func preset(_ name: String, _ exercises: [String]) -> Preset {
            Preset(name: name, exercises: exercises.map { .init(name: $0, groupKey: GroupGuess.group(for: $0)?.key) })
        }
        return [
            preset("Gym Machine Circuit", ["Chest Press", "Seated Row", "Leg Curl", "Leg Extension", "Shoulder Press",
                                           "Lat Pulldown", "Back Extension", "Abdominal Crunch", "Triceps",
                                           "Biceps Curl", "Leg Press"]),
            preset("Morning Core", ["Plank", "Russian Twist", "Leg Raise"]),
        ]
    }
}
