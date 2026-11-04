import Foundation

/// The three kinds of muscle group. A workout takes at most one of each.
public enum MuscleCategory: String, Codable, CaseIterable, Sendable {
    case upper, lower, core

    /// Total sets after which a group in this category is crossed out:
    /// one workout for upper body, two for lower body, four for core.
    public var threshold: Int {
        switch self {
        case .upper: return 3
        case .lower: return 6
        case .core: return 12
        }
    }

    /// The section heading on the home grid.
    public var title: String {
        switch self {
        case .upper: return "Upper body"
        case .lower: return "Lower body"
        case .core: return "Core"
        }
    }
}

/// One selectable cell of the home grid.
public struct MuscleGroup: Identifiable, Hashable, Sendable {
    /// Unique storage key. "Inner" appears twice in the grid, so it becomes
    /// "Inner (Thighs)" and "Inner (Chest)", the same keys the web app used.
    public let key: String
    /// The name shown in the grid, e.g. "Inner".
    public let name: String
    /// The body area row it sits in, e.g. "Thighs".
    public let area: String
    public let category: MuscleCategory
    public let noEquipment: [String]
    public let gym: [String]

    public var id: String { key }

    /// Every exercise, no-equipment ones first.
    public var allExercises: [String] { noEquipment + gym }
}

/// One row of the home grid: a body area label and its four groups.
public struct BodyAreaRow: Identifiable, Sendable {
    public let area: String
    public let category: MuscleCategory
    public let groups: [MuscleGroup]

    public var id: String { area }
}

/// One labeled section of the home grid: a category and its body-area rows.
public struct CategorySection: Identifiable, Sendable {
    public let category: MuscleCategory
    public let rows: [BodyAreaRow]

    public var id: String { category.rawValue }
}

public enum Catalog {
    /// The grid's three sections in workout order: upper body, lower body, core.
    public static let sections: [CategorySection] = MuscleCategory.allCases.map { category in
        CategorySection(category: category, rows: rows.filter { $0.category == category })
    }

    /// The seven body areas in section order, for picking stretches.
    public static var areas: [String] {
        sections.flatMap { $0.rows.map(\.area) }
    }

    /// Grid rows, top to bottom.
    public static let rows: [BodyAreaRow] = layout.map { row in
        let groups = row.names.map { name -> MuscleGroup in
            let key = keyOverrides[row.area + "|" + name] ?? name
            let lists = exercises[key] ?? (noEquipment: [], gym: [])
            return MuscleGroup(key: key, name: name, area: row.area, category: row.category,
                               noEquipment: lists.noEquipment, gym: lists.gym)
        }
        return BodyAreaRow(area: row.area, category: row.category, groups: groups)
    }

    /// All 28 groups in grid order.
    public static let groups: [MuscleGroup] = rows.flatMap(\.groups)

    private static let byKey: [String: MuscleGroup] =
        Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0) })

    public static func group(_ key: String) -> MuscleGroup? {
        byKey[key]
    }

    /// Sets needed to finish the whole program.
    public static var totalSets: Int {
        groups.reduce(0) { $0 + $1.category.threshold }
    }

    private static let layout: [(area: String, category: MuscleCategory, names: [String])] = [
        ("Core", .core, ["Rectus", "Transversal", "Oblique", "Lower Abs"]),
        ("Thighs", .lower, ["Quads", "Hams", "Inner", "Outer"]),
        ("Calves", .lower, ["Standing", "Seated", "Hips", "Tibs"]),
        ("Chest", .upper, ["Mid", "Upper", "Lower", "Inner"]),
        ("Back", .upper, ["Traps", "Lats", "Lower Back", "Neck"]),
        ("Shoulders", .upper, ["Front", "Lateral", "Rear", "Rotator"]),
        ("Arms", .upper, ["Biceps", "Triceps", "Forearm", "Grip"]),
    ]

    private static let keyOverrides: [String: String] = [
        "Thighs|Inner": "Inner (Thighs)",
        "Chest|Inner": "Inner (Chest)",
    ]
}

public enum ExerciseText {
    /// Splits a trailing parenthetical into a note, so
    /// "Step-Ups (on a sturdy chair)" shows as "Step-Ups" over "on a sturdy chair".
    /// Names with parentheses in the middle are left whole.
    public static func split(_ exercise: String) -> (title: String, note: String?) {
        guard exercise.hasSuffix(")"), let open = exercise.lastIndex(of: "(") else {
            return (exercise, nil)
        }
        let inner = exercise[exercise.index(after: open)..<exercise.index(before: exercise.endIndex)]
        guard !inner.contains(")") else { return (exercise, nil) }
        let title = exercise[..<open].trimmingCharacters(in: .whitespaces)
        return (title, String(inner))
    }
}
