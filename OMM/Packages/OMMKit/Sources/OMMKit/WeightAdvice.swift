import Foundation

/// The weight to try next on an exercise, from the reps logged last time.
/// The target is 8 to 12 reps a set:
/// - first set at 12 or more and last set at 9 or more: go up 5 pounds
/// - ticked "too heavy": go down 5 pounds, never up
/// - anything else, like 12, 10, 8: stay at the same weight
public struct WeightAdvice: Equatable, Sendable {
    public enum Direction: Sendable {
        case up, same, down
    }

    public static let step = 5.0
    public static let topReps = 12
    public static let lastSetFloor = 9

    public let direction: Direction
    public let pounds: Double

    /// nil when the weight isn't a number, or there are no reps and no "too heavy" tick.
    public init?(log: LiftLog) {
        guard let last = Double(log.weight.trimmingCharacters(in: .whitespaces)), last >= 0 else { return nil }
        if log.tooHeavy {
            direction = .down
            pounds = max(0, last - Self.step)
        } else if let first = log.reps.first, let final = log.reps.last {
            if first >= Self.topReps && final >= Self.lastSetFloor {
                direction = .up
                pounds = last + Self.step
            } else {
                direction = .same
                pounds = last
            }
        } else {
            return nil
        }
    }

    /// "40" or "37.5", the way the weight box shows it.
    public var weightText: String {
        Self.format(pounds)
    }

    /// One short line for the chip: "Try 40 lbs".
    public var label: String {
        switch direction {
        case .up: return "Try \(weightText) lbs"
        case .same: return "Stay at \(weightText) lbs"
        case .down: return "Go down to \(weightText) lbs"
        }
    }

    /// Why, in plain words.
    public var reason: String {
        switch direction {
        case .up: return "Last time your first set hit \(Self.topReps) and your last set hit \(Self.lastSetFloor) or more."
        case .same: return "Go up once your first set hits \(Self.topReps) and your last set hits \(Self.lastSetFloor) or more."
        case .down: return "You marked it too heavy last time."
        }
    }

    public static func format(_ pounds: Double) -> String {
        pounds == pounds.rounded() ? String(Int(pounds)) : String(format: "%.1f", pounds)
    }
}
