/// One gentle stretch for a body area.
public struct Stretch: Hashable, Sendable {
    public let name: String
    public let how: String
    public let area: String
    public let holdSeconds: Int
    /// Done once on each side, as two holds.
    public let eachSide: Bool
}

/// One hold in a stretch routine.
public struct StretchStep: Hashable, Sendable {
    public let stretch: Stretch
    /// "Left side", "Right side", or nil for stretches done once.
    public let side: String?

    public var title: String {
        side.map { "\(stretch.name), \($0.lowercased())" } ?? stretch.name
    }
}

/// Stretches for after a workout, or on their own. They never cross anything
/// off the grid or change the estimate.
public enum Stretches {
    public static let safetyNote = "Ease in to a gentle pull, never pain. Breathe slowly. Stop if anything hurts."

    public static let holdSeconds = 30

    /// Body area → two stretches.
    public static let byArea: [String: [Stretch]] = [
        "Core": [
            stretch("Cobra Lift", "Lie face down with your hands under your shoulders. Press up slowly until you feel a stretch across your belly. Keep your hips on the floor.", "Core"),
            stretch("Lying Twist", "Lie on your back with your knees bent. Let both knees fall to one side while your shoulders stay flat.", "Core", eachSide: true),
        ],
        "Thighs": [
            stretch("Standing Quad Pull", "Hold a wall or chair for balance. Bend one knee and hold that ankle behind you, knees side by side.", "Thighs", eachSide: true),
            stretch("Seated Hamstring Reach", "Sit with one leg straight and the other foot against your inner thigh. Reach toward the toes of the straight leg.", "Thighs", eachSide: true),
        ],
        "Calves": [
            stretch("Wall Calf Lean", "Hands on a wall, step one foot back with the heel down and the leg straight. Lean in until the calf stretches.", "Calves", eachSide: true),
            stretch("Step Heel Drop", "Stand on the edge of a step on the balls of your feet, holding a rail. Let your heels sink below the step.", "Calves"),
        ],
        "Chest": [
            stretch("Doorway Opener", "Rest your forearms on a door frame at shoulder height. Step forward gently until your chest opens up.", "Chest"),
            stretch("Hands-Behind Lift", "Clasp your hands behind your back, straighten your arms and lift them a little. Keep your chest up.", "Chest"),
        ],
        "Back": [
            stretch("Child's Pose", "Kneel, sit back toward your heels and walk your hands forward on the floor. Let your back relax.", "Back"),
            stretch("Knee Hug", "Lie on your back and pull both knees in toward your chest.", "Back"),
        ],
        "Shoulders": [
            stretch("Cross-Arm Pull", "Bring one arm straight across your chest and hold it above the elbow with the other hand.", "Shoulders", eachSide: true),
            stretch("Thread the Needle", "On hands and knees, slide one arm under your body along the floor and rest that shoulder down.", "Shoulders", eachSide: true),
        ],
        "Arms": [
            stretch("Overhead Triceps Reach", "Reach one hand down the middle of your upper back. Use the other hand to ease that elbow back.", "Arms", eachSide: true),
            stretch("Wrist and Forearm Pull", "Hold one arm out straight, palm up. Use the other hand to ease the fingers down and back.", "Arms", eachSide: true),
        ],
    ]

    /// Every hold for these areas, in the order given, each-side stretches split in two.
    public static func routine(areas: [String]) -> [StretchStep] {
        areas.flatMap { byArea[$0] ?? [] }.flatMap { stretch -> [StretchStep] in
            stretch.eachSide
                ? [StretchStep(stretch: stretch, side: "Left side"), StretchStep(stretch: stretch, side: "Right side")]
                : [StretchStep(stretch: stretch, side: nil)]
        }
    }

    /// Whole minutes the routine takes, rounded up.
    public static func minutes(for steps: [StretchStep]) -> Int {
        let seconds = steps.reduce(0) { $0 + $1.stretch.holdSeconds }
        return (seconds + 59) / 60
    }

    private static func stretch(_ name: String, _ how: String, _ area: String, eachSide: Bool = false) -> Stretch {
        Stretch(name: name, how: how, area: area, holdSeconds: holdSeconds, eachSide: eachSide)
    }
}
