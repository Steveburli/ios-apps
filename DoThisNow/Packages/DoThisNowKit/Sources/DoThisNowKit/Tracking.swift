import Foundation

/// Something you do often and time on the Track tab, like "Shower" or
/// "Commute to work".
public struct Activity: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// An SF Symbol name.
    public var symbol = "timer"
    /// Other names that count as this, so "Take a shower" in Reminders uses
    /// the shower's timings.
    public var aliases: [String] = []
    public var isExample = false

    public init(id: String = newID(), name: String, symbol: String = "timer") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }

    private enum CodingKeys: String, CodingKey { case id, name, symbol, aliases, isExample }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  symbol: try c.decodeIfPresent(String.self, forKey: .symbol) ?? "timer")
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
    }
}

/// One timed run of something, from the Track tab, a finished timer on the
/// Now tab, or a block on the Day.
public struct Timing: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var activityID: String?
    public var title: String
    public var start: Date
    public var seconds: Double
    public var isExample = false

    public init(id: String = newID(), activityID: String? = nil, title: String, start: Date, seconds: Double) {
        self.id = id
        self.activityID = activityID
        self.title = title
        self.start = start
        self.seconds = max(0, seconds)
    }

    public var minutes: Double {
        seconds / 60
    }

    public var end: Date {
        start.addingTimeInterval(seconds)
    }

    private enum CodingKeys: String, CodingKey { case id, activityID, title, start, seconds, isExample }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  activityID: try c.decodeIfPresent(String.self, forKey: .activityID),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  start: try c.decodeIfPresent(Date.self, forKey: .start) ?? Date(),
                  seconds: try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0)
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
    }
}

/// The Track tab's stopwatch.
public struct RunningTimer: Codable, Equatable, Sendable {
    public var activityID: String?
    public var title: String
    public var startedAt: Date

    public init(activityID: String?, title: String, startedAt: Date) {
        self.activityID = activityID
        self.title = title
        self.startedAt = startedAt
    }
}

/// How long something should take, and where that number came from.
public struct Estimate: Equatable, Sendable {
    public enum Basis: Equatable, Sendable {
        /// You set it.
        case custom
        /// From your timings: how many were averaged and how many were left out.
        case history(used: Int, outliers: Int)
        /// The task's own estimate.
        case source
        /// A guess from the words in the title.
        case guess
    }

    public let minutes: Int
    public let basis: Basis

    public init(minutes: Int, basis: Basis) {
        self.minutes = max(1, minutes)
        self.basis = basis
    }

    /// "your time", "average of 6 timings, 1 outlier left out", "a guess".
    public var detail: String {
        switch basis {
        case .custom:
            return "your time"
        case .history(let used, let outliers):
            let runs = used == 1 ? "timed once" : "average of \(used) timings"
            return outliers > 0 ? "\(runs), \(outliers) outlier\(outliers == 1 ? "" : "s") left out" : runs
        case .source:
            return "from the task"
        case .guess:
            return "a guess"
        }
    }

    public var isFromHistory: Bool {
        if case .history = basis { return true }
        return false
    }
}

public enum Estimator {
    /// Only the most recent timings count, since habits change.
    public static let window = 20

    private static let filler: Set<String> = ["the", "a", "an", "my", "to", "some", "of"]

    /// What two titles share when they're the same thing: "Mow the lawn!"
    /// and "mow lawn" both become "mow lawn".
    public static func key(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let kept = words.filter { !filler.contains($0) }
        return (kept.isEmpty ? words : kept).joined(separator: " ")
    }

    /// The usual length of something from past runs, in minutes, with
    /// outliers left out. Four or more runs use Tukey's fences (1.5 times
    /// the spread of the middle half past either quartile). Three runs drop
    /// any run under half or over double the middle one.
    public static func typical(_ samples: [Double]) -> (minutes: Double, used: Int, outliers: Int)? {
        let values = samples.filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return nil }
        var kept = values
        if values.count >= 4 {
            let q1 = quantile(values, 0.25), q3 = quantile(values, 0.75)
            let spread = q3 - q1
            kept = values.filter { $0 >= q1 - 1.5 * spread && $0 <= q3 + 1.5 * spread }
        } else if values.count == 3 {
            let middle = values[1]
            kept = values.filter { $0 >= middle / 2 && $0 <= middle * 2 }
        }
        let mean = kept.reduce(0, +) / Double(kept.count)
        return (mean, kept.count, values.count - kept.count)
    }

    /// Linear interpolation between the closest ranks of a sorted list.
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    /// Whole minutes under half an hour, then the nearest 5.
    public static func rounded(_ minutes: Double) -> Int {
        if minutes < 30 { return max(1, Int(minutes.rounded())) }
        return Int((minutes / 5).rounded()) * 5
    }

    /// First guesses by word, before there's any history. The first rule
    /// with a word in the title wins.
    private static let rules: [(words: Set<String>, minutes: Int)] = [
        (["text", "reply", "floss", "teeth", "trash", "recycling", "vitamins", "pills", "medication", "medicine"], 5),
        (["email", "emails", "pay", "bill", "bills", "order", "renew", "book", "schedule", "appointment", "dress",
          "dressed", "coffee", "plants", "feed", "unload", "dishwasher"], 10),
        (["call", "phone", "shower", "dishes", "tidy", "pack", "lunch", "fold"], 15),
        (["breakfast", "vacuum", "laundry", "review", "plan", "sweep", "stretch"], 20),
        (["walk", "read", "commute", "drive", "errand", "errands", "clean", "mop", "study", "practice", "learn",
          "research"], 30),
        (["gym", "workout", "run", "exercise", "mow", "cook", "dinner", "groceries", "grocery", "shopping", "yoga"], 45),
        (["meeting", "write", "report", "project", "presentation", "taxes", "budget"], 60),
    ]

    /// A rough length for a title nobody has timed yet: 30 minutes unless a
    /// word suggests otherwise.
    public static func guess(_ title: String) -> Int {
        let words = Set(key(title).split(separator: " ").map(String.init))
        return rules.first { !$0.words.isDisjoint(with: words) }?.minutes ?? 30
    }
}

extension PlannerState {
    public func activity(_ id: String?) -> Activity? {
        guard let id else { return nil }
        return activities.first { $0.id == id }
    }

    /// The activity a title belongs to, by its name or one of its other names.
    public func activity(matching title: String) -> Activity? {
        let key = Estimator.key(title)
        guard !key.isEmpty else { return nil }
        return activities.first { activity in
            Estimator.key(activity.name) == key || activity.aliases.contains { Estimator.key($0) == key }
        }
    }

    /// Past runs of something, newest first: the runs of its activity, plus
    /// any run with the same title.
    public func timings(for title: String, activityID: String? = nil) -> [Timing] {
        let activity = self.activity(activityID) ?? self.activity(matching: title)
        var keys: Set<String> = [Estimator.key(title)]
        if let activity {
            keys.insert(Estimator.key(activity.name))
            keys.formUnion(activity.aliases.map(Estimator.key))
        }
        keys.remove("")
        return timings
            .filter { timing in
                (activity != nil && timing.activityID == activity?.id) || keys.contains(Estimator.key(timing.title))
            }
            .sorted { $0.start > $1.start }
    }

    /// How long something should take: the time you set, else your recent
    /// timings without outliers, else the task's own estimate, else a guess.
    public func estimate(title: String, activityID: String? = nil, custom: Int? = nil, source: Int? = nil) -> Estimate {
        if let custom, custom > 0 { return Estimate(minutes: custom, basis: .custom) }
        let recent = timings(for: title, activityID: activityID).prefix(Estimator.window).map(\.minutes)
        if let typical = Estimator.typical(Array(recent)) {
            return Estimate(minutes: Estimator.rounded(typical.minutes),
                            basis: .history(used: typical.used, outliers: typical.outliers))
        }
        if let source, source > 0 { return Estimate(minutes: source, basis: .source) }
        return Estimate(minutes: Estimator.guess(title), basis: .guess)
    }

    // MARK: The Track tab's stopwatch

    /// Starts timing something. Whatever was running stops and is saved, so
    /// tapping one thing after another times a whole routine.
    @discardableResult
    public mutating func startTimer(activityID: String?, title: String, at now: Date) -> Timing? {
        let finished = stopTimer(at: now)
        running = RunningTimer(activityID: activityID, title: title, startedAt: now)
        return finished
    }

    /// Stops the stopwatch and saves the run. Runs under 20 seconds are
    /// treated as a mis-tap and dropped.
    @discardableResult
    public mutating func stopTimer(at now: Date) -> Timing? {
        guard let run = running else { return nil }
        running = nil
        let seconds = now.timeIntervalSince(run.startedAt)
        guard seconds >= 20 else { return nil }
        let timing = Timing(activityID: run.activityID, title: run.title, start: run.startedAt, seconds: seconds)
        timings.append(timing)
        return timing
    }

    public mutating func deleteActivity(_ id: String) {
        activities.removeAll { $0.id == id }
        timings.removeAll { $0.activityID == id }
        if running?.activityID == id { running = nil }
        for index in wake.routine.indices where wake.routine[index].activityID == id {
            wake.routine[index].activityID = nil
        }
        if wake.commute.activityID == id { wake.commute.activityID = nil }
    }
}
