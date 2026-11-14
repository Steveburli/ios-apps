import Foundation

/// One gentle stretch or yoga pose.
public struct Stretch: Hashable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case stretch, yoga

        public var title: String {
            switch self {
            case .stretch: return "Stretch"
            case .yoga: return "Yoga"
            }
        }
    }

    /// Standing moves come first in a routine, so you get down to the floor once.
    public enum Posture: Int, Comparable, Sendable {
        case standing, floor

        public static func < (lhs: Posture, rhs: Posture) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Stable id, saved in routines and used to find the picture.
    public let id: String
    public let name: String
    public let how: String
    /// The body area row it's listed under, e.g. "Thighs".
    public let area: String
    public let kind: Kind
    public let posture: Posture
    /// Grid group keys it stretches, for routines built from what you trained.
    public let groups: [String]
    /// The suggested hold. Saved routines can change it.
    public let holdSeconds: Int
    /// Done once on each side, as two holds.
    public let eachSide: Bool
}

/// One hold in a stretch routine.
public struct StretchStep: Hashable, Sendable {
    public let stretch: Stretch
    /// "Left side", "Right side", or nil for stretches done once.
    public let side: String?
    public let holdSeconds: Int

    public init(stretch: Stretch, side: String?, holdSeconds: Int? = nil) {
        self.stretch = stretch
        self.side = side
        self.holdSeconds = holdSeconds ?? stretch.holdSeconds
    }

    public var title: String {
        side.map { "\(stretch.name), \($0.lowercased())" } ?? stretch.name
    }
}

/// Stretches and yoga poses: after a workout, from the Stretch tab, or in
/// routines people save. They never cross anything off the grid or change
/// the estimate. The wording and pictures are this app's own.
public enum Stretches {
    public static let safetyNote = "Ease in to a gentle pull, never pain. Breathe slowly. Stop if anything hurts."

    public static let holdSeconds = 30

    /// Hold lengths offered when building a routine.
    public static let holdChoices = [20, 30, 45, 60]

    /// Every move, grouped by body area in grid order.
    public static let library: [Stretch] = [
        // Core
        move("cobra-lift", "Cobra Lift", "Lie face down with your hands under your shoulders. Press up slowly until you feel a stretch across your belly. Keep your hips on the floor.",
             "Core", .floor, ["Rectus", "Lower Abs"]),
        move("sphinx", "Sphinx Pose", "Lie face down and prop yourself up on your forearms, elbows under your shoulders. Let your belly soften toward the floor and keep your neck long.",
             "Core", .floor, ["Rectus", "Lower Abs", "Lower Back"], kind: .yoga),
        move("lying-twist", "Lying Twist", "Lie on your back with your knees bent. Let both knees fall to one side while your shoulders stay flat.",
             "Core", .floor, ["Oblique", "Transversal", "Lower Back"], eachSide: true),
        move("side-reach", "Standing Side Reach", "Stand tall with your feet hip-width apart. Reach one arm up and over your head and lean gently to the other side.",
             "Core", .standing, ["Oblique", "Lats", "Transversal"], eachSide: true),
        move("seated-twist", "Seated Spinal Twist", "Sit with one leg straight. Bend the other knee and set that foot outside the straight leg. Hug the knee and turn gently toward it, one hand on the floor behind you.",
             "Core", .floor, ["Oblique", "Transversal", "Lower Back"], kind: .yoga, eachSide: true),
        // Thighs
        move("quad-pull", "Standing Quad Pull", "Hold a wall or chair for balance. Bend one knee and hold that ankle behind you, knees side by side.",
             "Thighs", .standing, ["Quads", "Hips"], eachSide: true),
        move("hamstring-reach", "Seated Hamstring Reach", "Sit with one leg straight and the other foot against your inner thigh. Reach toward the toes of the straight leg.",
             "Thighs", .floor, ["Hams", "Lower Back"], eachSide: true),
        move("forward-fold", "Forward Fold", "Stand with your knees soft. Hinge at the hips and let your upper body hang toward the floor. Bend your knees as much as you need.",
             "Thighs", .standing, ["Hams", "Lower Back", "Standing"], kind: .yoga),
        move("butterfly", "Butterfly", "Sit with the soles of your feet together and your knees falling out. Hold your feet and sit tall. Let your knees sink on their own.",
             "Thighs", .floor, ["Inner (Thighs)", "Hips"]),
        move("figure-four", "Figure Four", "Lie on your back with your knees bent. Cross one ankle over the other knee, then pull the lower leg gently toward you.",
             "Thighs", .floor, ["Outer", "Hips"], eachSide: true),
        move("low-lunge", "Low Lunge", "Step one foot forward and lower the back knee to the floor, on a pad if you like. Ease your hips forward and lift your arms.",
             "Thighs", .floor, ["Quads", "Hips"], kind: .yoga, eachSide: true),
        move("warrior-two", "Warrior II", "Stand with your feet wide. Turn one foot out and bend that knee over the ankle. Stretch your arms out to the sides and look over the front hand.",
             "Thighs", .standing, ["Inner (Thighs)", "Quads", "Hips"], kind: .yoga, eachSide: true),
        move("happy-baby", "Happy Baby", "Lie on your back, bring your knees toward your armpits and hold the outsides of your feet. Let your lower back rest on the floor.",
             "Thighs", .floor, ["Inner (Thighs)", "Hips", "Lower Back"], kind: .yoga),
        move("bridge", "Bridge Pose", "Lie on your back with your knees bent and feet flat. Press through your feet and lift your hips until your body is a straight slope from knees to shoulders.",
             "Thighs", .floor, ["Hips", "Quads", "Rectus"], kind: .yoga),
        // Calves
        move("wall-calf", "Wall Calf Lean", "Hands on a wall, step one foot back with the heel down and the leg straight. Lean in until the calf stretches.",
             "Calves", .standing, ["Standing"], eachSide: true),
        move("heel-drop", "Step Heel Drop", "Stand on the edge of a step on the balls of your feet, holding a rail. Let your heels sink below the step.",
             "Calves", .standing, ["Standing", "Seated"]),
        move("calf-towel", "Seated Towel Calf Pull", "Sit with one leg straight and loop a towel around the ball of that foot. Pull the towel gently toward you with a straight knee.",
             "Calves", .floor, ["Seated", "Standing"], eachSide: true),
        move("shin-stretch", "Standing Shin Stretch", "Hold a wall. Point one foot behind you and rest the top of the toes on the floor. Press the ankle gently toward the floor.",
             "Calves", .standing, ["Tibs"], eachSide: true),
        move("downward-dog", "Downward Dog", "From hands and knees, tuck your toes and lift your hips up and back into an upside-down V. Keep your knees bent if your hamstrings are tight.",
             "Calves", .floor, ["Standing", "Hams", "Lats"], kind: .yoga),
        // Chest
        move("doorway-opener", "Doorway Opener", "Rest your forearms on a door frame at shoulder height. Step forward gently until your chest opens up.",
             "Chest", .standing, ["Mid", "Upper", "Inner (Chest)", "Front"]),
        move("hands-behind", "Hands-Behind Lift", "Clasp your hands behind your back, straighten your arms and lift them a little. Keep your chest up.",
             "Chest", .standing, ["Mid", "Lower", "Front"]),
        move("wall-chest", "Wall Chest Turn", "Put one palm on a wall at shoulder height with your arm straight. Turn your feet and chest slowly away from the wall.",
             "Chest", .standing, ["Mid", "Inner (Chest)", "Biceps"], eachSide: true),
        move("puppy", "Puppy Pose", "From hands and knees, walk your hands forward and lower your chest toward the floor. Keep your hips over your knees.",
             "Chest", .floor, ["Upper", "Lower", "Lats", "Front"], kind: .yoga),
        // Back
        move("childs-pose", "Child's Pose", "Kneel, sit back toward your heels and walk your hands forward on the floor. Let your back relax.",
             "Back", .floor, ["Lats", "Lower Back"], kind: .yoga),
        move("knee-hug", "Knee Hug", "Lie on your back and pull both knees in toward your chest.",
             "Back", .floor, ["Lower Back"]),
        move("neck-tilt", "Neck Side Tilt", "Sit or stand tall. Tip one ear toward that shoulder and let the hand on that side rest lightly on your head. Keep the other shoulder down.",
             "Back", .standing, ["Neck", "Traps"], eachSide: true),
        move("cat-cow", "Cat-Cow", "On hands and knees, round your back up like a cat, then let it sag gently as you lift your head. Move slowly with your breath.",
             "Back", .floor, ["Lower Back", "Rectus", "Neck"], kind: .yoga),
        // Shoulders
        move("cross-arm", "Cross-Arm Pull", "Bring one arm straight across your chest and hold it above the elbow with the other hand.",
             "Shoulders", .standing, ["Rear", "Lateral", "Rotator"], eachSide: true),
        move("thread-needle", "Thread the Needle", "On hands and knees, slide one arm under your body along the floor and rest that shoulder down.",
             "Shoulders", .floor, ["Rear", "Rotator", "Traps"], eachSide: true),
        move("eagle-arms", "Eagle Arms", "Cross one arm under the other at the elbows and bring your palms together, or hold your shoulders. Lift your elbows a little.",
             "Shoulders", .standing, ["Rear", "Traps", "Rotator"], kind: .yoga, eachSide: true),
        move("upward-reach", "Upward Reach", "Stand tall and reach both arms straight overhead, palms facing. Let your ribs lift without arching your back.",
             "Shoulders", .standing, ["Lats", "Lateral", "Front", "Lower"], kind: .yoga),
        // Arms
        move("triceps-reach", "Overhead Triceps Reach", "Reach one hand down the middle of your upper back. Use the other hand to ease that elbow back.",
             "Arms", .standing, ["Triceps", "Lats"], eachSide: true),
        move("wrist-pull", "Wrist and Forearm Pull", "Hold one arm out straight, palm up. Use the other hand to ease the fingers down and back.",
             "Arms", .standing, ["Forearm", "Grip"], eachSide: true),
        move("biceps-wall", "Biceps Wall Turn", "Put one palm on a wall behind you, a little below shoulder height, thumb down. Turn your body slowly away until the front of the arm stretches.",
             "Arms", .standing, ["Biceps", "Front"], eachSide: true),
        move("prayer-hands", "Prayer Hands", "Press your palms together in front of your chest, fingers up. Lower your hands slowly until your forearms stretch, palms still together.",
             "Arms", .standing, ["Forearm", "Grip"]),
    ]

    private static let byID: [String: Stretch] = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })

    public static func stretch(id: String) -> Stretch? {
        byID[id]
    }

    /// Every move listed under an area, in library order.
    public static func moves(in area: String) -> [Stretch] {
        library.filter { $0.area == area }
    }

    /// Every move that stretches a grid group.
    public static func moves(for groupKey: String) -> [Stretch] {
        library.filter { $0.groups.contains(groupKey) }
    }

    /// Body area → the two stretches used after a workout and in "By area".
    public static let byArea: [String: [Stretch]] = ([
        "Core": ["cobra-lift", "lying-twist"],
        "Thighs": ["quad-pull", "hamstring-reach"],
        "Calves": ["wall-calf", "heel-drop"],
        "Chest": ["doorway-opener", "hands-behind"],
        "Back": ["childs-pose", "knee-hug"],
        "Shoulders": ["cross-arm", "thread-needle"],
        "Arms": ["triceps-reach", "wrist-pull"],
    ] as [String: [String]]).mapValues { ids in ids.compactMap { byID[$0] } }

    /// Every hold for these areas, in the order given, each-side stretches split in two.
    public static func routine(areas: [String]) -> [StretchStep] {
        steps(for: areas.flatMap { byArea[$0] ?? [] })
    }

    /// The holds for these moves in order, each-side moves split in two.
    public static func steps(for moves: [Stretch], holdSeconds: Int? = nil) -> [StretchStep] {
        moves.flatMap { stretch in steps(for: stretch, holdSeconds: holdSeconds ?? stretch.holdSeconds) }
    }

    public static func steps(for stretch: Stretch, holdSeconds: Int) -> [StretchStep] {
        stretch.eachSide
            ? [StretchStep(stretch: stretch, side: "Left side", holdSeconds: holdSeconds),
               StretchStep(stretch: stretch, side: "Right side", holdSeconds: holdSeconds)]
            : [StretchStep(stretch: stretch, side: nil, holdSeconds: holdSeconds)]
    }

    /// Whole minutes the routine takes, rounded up.
    public static func minutes(for steps: [StretchStep]) -> Int {
        (seconds(for: steps) + 59) / 60
    }

    public static func seconds(for steps: [StretchStep]) -> Int {
        steps.reduce(0) { $0 + $1.holdSeconds }
    }

    private static func move(_ id: String, _ name: String, _ how: String, _ area: String,
                             _ posture: Stretch.Posture, _ groups: [String],
                             kind: Stretch.Kind = .stretch, eachSide: Bool = false) -> Stretch {
        Stretch(id: id, name: name, how: how, area: area, kind: kind, posture: posture,
                groups: groups, holdSeconds: holdSeconds, eachSide: eachSide)
    }
}

/// A stretch routine someone built and named, saved apart from the program so
/// Reset Program keeps it.
public struct StretchRoutine: Codable, Equatable, Identifiable, Sendable {
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var stretchID: String
        /// Seconds per hold (per side for each-side moves).
        public var holdSeconds: Int

        public init(id: UUID = UUID(), stretchID: String, holdSeconds: Int = Stretches.holdSeconds) {
            self.id = id
            self.stretchID = stretchID
            self.holdSeconds = holdSeconds
        }

        public var stretch: Stretch? {
            Stretches.stretch(id: stretchID)
        }
    }

    public var id: UUID
    public var name: String
    public var items: [Item]

    public init(id: UUID = UUID(), name: String = "", items: [Item] = []) {
        self.id = id
        self.name = name
        self.items = items
    }

    /// Every hold in order. Moves no longer in the library are left out.
    public var steps: [StretchStep] {
        items.flatMap { item -> [StretchStep] in
            guard let stretch = item.stretch else { return [] }
            return Stretches.steps(for: stretch, holdSeconds: item.holdSeconds)
        }
    }

    /// Saveable: a name and at least one move.
    public var isReady: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !steps.isEmpty
    }
}

/// Builds the Stretch tab's "For you today" routine from what was trained.
public enum StretchPlanner {
    /// Lengths offered for the automatic routine, in minutes.
    public static let lengthChoices = [5, 10, 15]
    public static let defaultMinutes = 10

    /// Groups trained today or yesterday, most recent first: the ones likely to be sore.
    public static func soreGroups(in program: ProgramState, now: Date, calendar: Calendar = .current) -> [MuscleGroup] {
        Catalog.groups
            .filter { group in
                guard let days = program.daysSinceTrained(group, now: now, calendar: calendar) else { return false }
                return days <= 1
            }
            .sorted { (program.lastTrained[$0.key] ?? .distantPast) > (program.lastTrained[$1.key] ?? .distantPast) }
    }

    /// The groups likely to come up next: the ones picked on the home grid if
    /// any, otherwise one unfinished group per section (upper, lower, core),
    /// the one trained longest ago. Groups in `excluding` are skipped.
    public static func upcomingGroups(in program: ProgramState, picked: [String],
                                      excluding: [MuscleGroup] = []) -> [MuscleGroup] {
        let skip = Set(excluding.map(\.key))
        let pickedGroups = picked.compactMap(Catalog.group).filter { !skip.contains($0.key) }
        if !picked.isEmpty { return pickedGroups }
        return MuscleCategory.allCases.compactMap { category in
            Catalog.groups
                .filter { $0.category == category && !program.isDone($0) && !skip.contains($0.key) }
                .min { (program.lastTrained[$0.key] ?? .distantPast) < (program.lastTrained[$1.key] ?? .distantPast) }
        }
    }

    /// Moves for these groups that fit in about `minutes`, taking turns so
    /// every group gets one before any gets a second, standing moves first.
    public static func routine(for groups: [MuscleGroup], minutes: Int,
                               holdSeconds: Int = Stretches.holdSeconds) -> [StretchStep] {
        let budget = minutes * 60
        let lists = groups.map { Stretches.moves(for: $0.key) }
        var chosen: [Stretch] = []
        var used = 0
        let rounds = lists.map(\.count).max() ?? 0
        for round in 0..<rounds {
            for list in lists where round < list.count {
                let stretch = list[round]
                guard !chosen.contains(stretch) else { continue }
                let cost = holdSeconds * (stretch.eachSide ? 2 : 1)
                if used + cost <= budget || chosen.isEmpty {
                    chosen.append(stretch)
                    used += cost
                }
            }
        }
        let ordered = chosen.enumerated()
            .sorted { ($0.element.posture, $0.offset) < ($1.element.posture, $1.offset) }
            .map(\.element)
        return Stretches.steps(for: ordered, holdSeconds: holdSeconds)
    }
}
