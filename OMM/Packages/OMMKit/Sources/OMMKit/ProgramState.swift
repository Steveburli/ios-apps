import Foundation

/// Everything the program remembers between launches. Same shape as the web
/// app's four localStorage keys.
public struct ProgramState: Codable, Equatable, Sendable {
    /// Group key → total sets recorded.
    public var progress: [String: Int]
    /// "groupKey|exercise" → last weight entered, as typed.
    public var weights: [String: String]
    /// When the first workout was started.
    public var startDate: Date?
    /// "yyyy-MM-dd" → sets completed that day.
    public var dailySets: [String: Int]

    public init(progress: [String: Int] = [:], weights: [String: String] = [:],
                startDate: Date? = nil, dailySets: [String: Int] = [:]) {
        self.progress = progress
        self.weights = weights
        self.startDate = startDate
        self.dailySets = dailySets
    }

    public func setsDone(_ group: MuscleGroup) -> Int {
        progress[group.key] ?? 0
    }

    /// A finished group is crossed out on the grid and can't be picked.
    public func isDone(_ group: MuscleGroup) -> Bool {
        setsDone(group) >= group.category.threshold
    }

    /// Sets still needed across all groups.
    public var remainingSets: Int {
        Catalog.groups.reduce(0) { $0 + max(0, $1.category.threshold - setsDone($1)) }
    }

    public var isComplete: Bool {
        remainingSets == 0
    }

    /// Average sets per workout day, counting only days with sets.
    public var averageSetsPerDay: Double? {
        let counts = dailySets.values.filter { $0 > 0 }
        guard !counts.isEmpty else { return nil }
        return Double(counts.reduce(0, +)) / Double(counts.count)
    }

    /// Workout days left at the current pace: 0 once complete, nil before
    /// the first finished workout.
    public var estimatedDaysRemaining: Int? {
        if isComplete { return 0 }
        guard let average = averageSetsPerDay, average > 0 else { return nil }
        return Int((Double(remainingSets) / average).rounded(.up))
    }

    public static func weightKey(group: MuscleGroup, exercise: String) -> String {
        group.key + "|" + exercise
    }

    public func weight(for group: MuscleGroup, exercise: String) -> String? {
        weights[Self.weightKey(group: group, exercise: exercise)]
    }

    /// Sets the start date the first time a workout begins.
    public mutating func markStarted(at date: Date) {
        if startDate == nil { startDate = date }
    }

    /// Adds a finished workout: `setsPerGroup` sets to each group, and the
    /// workout's total to the day.
    public mutating func recordWorkout(groupKeys: [String], setsPerGroup: Int, dayKey: String) {
        for key in groupKeys {
            progress[key, default: 0] += setsPerGroup
        }
        dailySets[dayKey, default: 0] += groupKeys.count * setsPerGroup
    }

    /// Stores a weight as typed. A blank value clears it.
    public mutating func setWeight(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        weights[key] = trimmed.isEmpty ? nil : trimmed
    }
}

public enum DayKey {
    /// "yyyy-MM-dd" for the calendar day `date` falls on.
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Calendar days from `start` to `end`, counting both ends. Never less than 1.
    public static func daysInclusive(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: end)).day ?? 0
        return max(1, days + 1)
    }
}
