import Foundation

/// A saved routine that logs in one tap, like a circuit of gym machines with
/// no time to use the app in between. Each exercise counts as one set for its
/// muscle group. People make their own; none are built in.
public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public struct Exercise: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        /// The grid group it counts toward; nil until one is picked.
        public var groupKey: String?

        public init(id: UUID = UUID(), name: String = "", groupKey: String? = nil) {
            self.id = id
            self.name = name
            self.groupKey = groupKey
        }

        public var group: MuscleGroup? {
            groupKey.flatMap(Catalog.group)
        }
    }

    /// Sets one tap adds to one group.
    public struct GroupSets: Equatable, Sendable {
        public let group: MuscleGroup
        public let sets: Int
    }

    public var id: UUID
    public var name: String
    public var exercises: [Exercise]

    public init(id: UUID = UUID(), name: String = "", exercises: [Exercise] = []) {
        self.id = id
        self.name = name
        self.exercises = exercises
    }

    /// What one tap logs, in grid order. Two machines for the same group give it two sets.
    public var setsByGroup: [GroupSets] {
        var counts: [String: Int] = [:]
        for exercise in exercises {
            if let group = exercise.group { counts[group.key, default: 0] += 1 }
        }
        return Catalog.sections.flatMap { $0.rows.flatMap(\.groups) }.compactMap { group in
            counts[group.key].map { GroupSets(group: group, sets: $0) }
        }
    }

    public var totalSets: Int {
        exercises.filter { $0.group != nil }.count
    }

    /// Saveable: a name, at least one exercise, and a group for every exercise.
    public var isReady: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !exercises.isEmpty
            && exercises.allSatisfy { $0.group != nil }
    }
}

extension ProgramState {
    /// Logs one tap of a preset: a set per exercise to its group, the fade,
    /// and the day's sets. Only sets that still count toward an unfinished
    /// group go into the day's total, so extra sets don't skew the estimate.
    /// Returns those counted sets.
    @discardableResult
    public mutating func recordPreset(_ preset: Preset, at date: Date, calendar: Calendar = .current) -> Int {
        let entries = preset.setsByGroup
        var counted = 0
        for entry in entries {
            counted += min(entry.sets, max(0, entry.group.category.threshold - setsDone(entry.group)))
            progress[entry.group.key, default: 0] += entry.sets
        }
        if counted > 0 {
            dailySets[DayKey.string(for: date, calendar: calendar), default: 0] += counted
        }
        markStarted(at: date)
        markTrained(groupKeys: entries.map(\.group.key), at: date)
        return counted
    }
}

/// Guesses a muscle group from a typed exercise or machine name, so a preset
/// fills in quickly. Only a starting point: the person can change it.
public enum GroupGuess {
    /// Checked in order; the first rule with a matching phrase wins.
    private static let rules: [(phrases: [String], key: String)] = [
        (["calf", "calves"], "Standing"),
        (["leg press", "leg extension", "quad", "squat", "lunge"], "Quads"),
        (["back extension", "hyperextension", "lower back", "deadlift"], "Lower Back"),
        (["leg curl", "hamstring", "hams"], "Hams"),
        (["abduct", "outer thigh"], "Outer"),
        (["adduct", "inner thigh"], "Inner (Thighs)"),
        (["glute", "hip thrust", "kickback"], "Hips"),
        (["tibialis", "shin"], "Tibs"),
        (["pulldown", "pull-down", "pull-up", "pullup", "chin-up", "row", "lat "], "Lats"),
        (["shrug", "trap"], "Traps"),
        (["neck"], "Neck"),
        (["incline"], "Upper"),
        (["decline", "dip"], "Lower"),
        (["lateral raise", "side raise"], "Lateral"),
        (["rear delt", "reverse fly", "face pull"], "Rear"),
        (["rotator", "external rotation", "internal rotation"], "Rotator"),
        (["chest", "pec", "bench press", "fly", "flye", "push-up", "pushup"], "Mid"),
        (["shoulder", "overhead press", "military press"], "Front"),
        (["wrist", "forearm"], "Forearm"),
        (["tricep"], "Triceps"),
        (["bicep", "curl"], "Biceps"),
        (["grip", "farmer"], "Grip"),
        (["oblique", "twist", "side bend", "rotary torso", "torso rotation"], "Oblique"),
        (["leg raise", "reverse crunch", "knee raise"], "Lower Abs"),
        (["plank", "pallof", "rollout"], "Transversal"),
        (["crunch", "abdominal", "sit-up", "situp", "abs"], "Rectus"),
    ]

    public static func group(for name: String) -> MuscleGroup? {
        let text = " " + name.lowercased() + " "
        for rule in rules where rule.phrases.contains(where: { text.contains($0) }) {
            return Catalog.group(rule.key)
        }
        return nil
    }
}
