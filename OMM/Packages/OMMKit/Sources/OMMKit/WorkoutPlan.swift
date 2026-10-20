import Foundation

/// The screens of one workout: three rounds of upper → lower → core.
public struct WorkoutPlan: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let groupKey: String
        /// 1-based round number ("Set 2 of 3").
        public let set: Int

        public init(groupKey: String, set: Int) {
            self.groupKey = groupKey
            self.set = set
        }
    }

    public static let setsPerGroup = 3
    public static let durationRange: ClosedRange<Int> = 9...90
    public static let durationStep = 3
    public static let defaultDuration = 27

    /// The chosen groups in upper, lower, core order.
    public let groupKeys: [String]
    public let steps: [Step]
    /// Rest after each set: the workout's time split evenly across its sets,
    /// minus 30 seconds for doing the set. 27 minutes over 9 sets is 2:30.
    public let restSeconds: Int

    public init(groupKeys: [String], durationMinutes: Int) {
        var steps: [Step] = []
        for set in 1...Self.setsPerGroup {
            for key in groupKeys {
                steps.append(Step(groupKey: key, set: set))
            }
        }
        self.groupKeys = groupKeys
        self.steps = steps
        if steps.isEmpty {
            restSeconds = 0
        } else {
            let perStep = (Double(durationMinutes * 60) / Double(steps.count)).rounded()
            restSeconds = max(0, Int(perStep) - 30)
        }
    }
}

/// The home grid's picks: at most one group per category.
public struct GroupSelection: Equatable, Sendable {
    private var picks: [MuscleCategory: String] = [:]

    public init() {}

    public subscript(category: MuscleCategory) -> String? {
        picks[category]
    }

    public func contains(_ group: MuscleGroup) -> Bool {
        picks[group.category] == group.key
    }

    /// Picks the group, replacing any other in its category, or unpicks it.
    public mutating func toggle(_ group: MuscleGroup) {
        picks[group.category] = contains(group) ? nil : group.key
    }

    /// Picked keys in upper, lower, core order.
    public var orderedKeys: [String] {
        MuscleCategory.allCases.compactMap { picks[$0] }
    }

    public var isEmpty: Bool {
        picks.isEmpty
    }

    public mutating func clear() {
        picks.removeAll()
    }

    /// Drops picks that have since been finished.
    public mutating func removeCompleted(in state: ProgramState) {
        for (category, key) in picks {
            if let group = Catalog.group(key), state.isDone(group) {
                picks[category] = nil
            }
        }
    }
}
