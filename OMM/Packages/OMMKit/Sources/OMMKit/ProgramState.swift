import Foundation

/// What you did on one exercise the last time you logged reps for it.
public struct LiftLog: Codable, Equatable, Sendable {
    /// Pounds, as typed.
    public var weight: String
    /// Reps for each set, in order.
    public var reps: [Int]
    /// Ticked when form slipped, even if the reps were there.
    public var tooHeavy: Bool

    public init(weight: String, reps: [Int], tooHeavy: Bool = false) {
        self.weight = weight
        self.reps = reps
        self.tooHeavy = tooHeavy
    }
}

/// Everything the program remembers between launches. The first four fields
/// are the web app's four localStorage keys.
public struct ProgramState: Codable, Equatable, Sendable {
    /// Group key → total sets recorded.
    public var progress: [String: Int]
    /// "groupKey|exercise" → last weight entered, as typed.
    public var weights: [String: String]
    /// When the first workout was started.
    public var startDate: Date?
    /// "yyyy-MM-dd" → sets completed that day.
    public var dailySets: [String: Int]
    /// Group key → when it was last trained. Drives the grid's fade.
    public var lastTrained: [String: Date]
    /// "groupKey|exercise" → the last logged reps. Drives the weight suggestion.
    public var lifts: [String: LiftLog]

    /// Days until a trained group looks fully fresh on the grid again.
    public static let recoveryDays = 7

    public init(progress: [String: Int] = [:], weights: [String: String] = [:],
                startDate: Date? = nil, dailySets: [String: Int] = [:],
                lastTrained: [String: Date] = [:], lifts: [String: LiftLog] = [:]) {
        self.progress = progress
        self.weights = weights
        self.startDate = startDate
        self.dailySets = dailySets
        self.lastTrained = lastTrained
        self.lifts = lifts
    }

    private enum CodingKeys: String, CodingKey {
        case progress, weights, startDate, dailySets, lastTrained, lifts
    }

    /// Saves from before a field existed still load, with that field empty.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        progress = try container.decodeIfPresent([String: Int].self, forKey: .progress) ?? [:]
        weights = try container.decodeIfPresent([String: String].self, forKey: .weights) ?? [:]
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        dailySets = try container.decodeIfPresent([String: Int].self, forKey: .dailySets) ?? [:]
        lastTrained = try container.decodeIfPresent([String: Date].self, forKey: .lastTrained) ?? [:]
        lifts = try container.decodeIfPresent([String: LiftLog].self, forKey: .lifts) ?? [:]
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

    /// Calendar days since the group was last trained: 0 the same day, nil if never.
    public func daysSinceTrained(_ group: MuscleGroup, now: Date, calendar: Calendar = .current) -> Int? {
        guard let date = lastTrained[group.key] else { return nil }
        return DayKey.daysInclusive(from: date, to: now, calendar: calendar) - 1
    }

    /// 1 on the day a group is trained, fading evenly to 0 after `recoveryDays`.
    /// 0 for groups never trained.
    public func freshness(of group: MuscleGroup, now: Date, calendar: Calendar = .current) -> Double {
        guard let days = daysSinceTrained(group, now: now, calendar: calendar) else { return 0 }
        return max(0, 1 - Double(days) / Double(Self.recoveryDays))
    }

    public static func weightKey(group: MuscleGroup, exercise: String) -> String {
        group.key + "|" + exercise
    }

    public func weight(for group: MuscleGroup, exercise: String) -> String? {
        weights[Self.weightKey(group: group, exercise: exercise)]
    }

    public func lift(for group: MuscleGroup, exercise: String) -> LiftLog? {
        lifts[Self.weightKey(group: group, exercise: exercise)]
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

    public mutating func markTrained(groupKeys: [String], at date: Date) {
        for key in groupKeys {
            lastTrained[key] = date
        }
    }

    /// Stores a weight as typed. A blank value clears it.
    public mutating func setWeight(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        weights[key] = trimmed.isEmpty ? nil : trimmed
    }

    /// Saves the reps from the weight sheet. Reps or a "too heavy" tick replace
    /// the log. With neither, the old log stays if the weight didn't change, so
    /// an exercise you skipped keeps its suggestion, and goes if it did.
    public mutating func logLift(forKey key: String, weight: String, reps: [Int], tooHeavy: Bool) {
        let weight = weight.trimmingCharacters(in: .whitespaces)
        if weight.isEmpty {
            lifts[key] = nil
        } else if !reps.isEmpty || tooHeavy {
            lifts[key] = LiftLog(weight: weight, reps: reps, tooHeavy: tooHeavy)
        } else if let old = lifts[key], old.weight != weight {
            lifts[key] = nil
        }
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
