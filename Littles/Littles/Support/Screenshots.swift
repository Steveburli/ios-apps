import Foundation
import LittlesKit

/// The cloud build launches the app with `-screenshots <screen>` to photograph
/// each screen with sample data: today, bottle, meal, food, fooddetail,
/// mealplan, dinner, play, activity, schedule, import, grow, growth, health,
/// memories, tips, family, night or welcome.
/// Nothing here runs in normal use, and it never saves.
enum Screenshots {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool {
        screen != nil
    }

    static func shows(_ name: String) -> Bool {
        screen == name
    }

    /// The baby, except on screens about the preschooler.
    static var kidID: String {
        switch screen {
        case "schedule", "tips": return Sample.bigID
        default: return Sample.babyID
        }
    }

    /// Which Grow section a screen opens.
    static var growSection: GrowSection {
        switch screen {
        case "tips": return .tips
        case "growth": return .growth
        case "health": return .health
        case "memories": return .memories
        default: return .milestones
        }
    }

    /// Which tab the screen lives on.
    static var tab: AppTab {
        switch screen {
        case "food", "fooddetail", "mealplan", "dinner": return .food
        case "play", "activity": return .play
        case "schedule", "import": return .schedule
        case "grow", "growth", "tips", "health", "memories": return .grow
        default: return .today
        }
    }
}
