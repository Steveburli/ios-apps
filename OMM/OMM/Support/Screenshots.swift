import Foundation
import OMMKit

/// The cloud build launches the app with `-screenshots <screen>` to photograph
/// each screen with sample data: home, workout, weights or complete.
/// Nothing here runs in normal use.
enum Screenshots {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool {
        screen != nil
    }

    /// Twelve days in: some groups crossed out, a few weights remembered.
    static func sampleProgram(now: Date = Date()) -> ProgramState {
        var state = ProgramState()
        state.startDate = now.addingTimeInterval(-12 * 86_400)
        for key in ["Mid", "Upper", "Traps", "Lats", "Biceps", "Triceps", "Rear"] {
            state.progress[key] = 3
        }
        for key in ["Quads", "Standing"] {
            state.progress[key] = 6
        }
        state.progress["Hams"] = 3
        state.progress["Rectus"] = 12
        state.progress["Oblique"] = 6
        for daysAgo in [1, 3, 5, 7, 9, 12] {
            state.dailySets[DayKey.string(for: now.addingTimeInterval(Double(-daysAgo) * 86_400))] = 9
        }
        state.weights["Front|Dumbbell Shoulder Press"] = "35"
        state.weights["Front|Arnold Press"] = "30"
        state.weights["Front|Front Raises (Dumbbell/Plate)"] = "15"
        state.weights["Hams|Romanian Deadlift (Barbell/Dumbbell)"] = "95"
        state.weights["Oblique|Dumbbell Side Bends"] = "40"
        return state
    }
}
