import Foundation

/// One suggestion on the "Do this." card.
public struct Candidate: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// One task.
        case task
        /// Two or more errands in one trip.
        case errands
        /// Two to four little things around the house.
        case sweep
    }

    public let kind: Kind
    public let id: String
    public let tasks: [TaskItem]
    public let title: String
    public let minutes: Int
    public let score: Double
    public let reasons: [String]
    /// The time is enough to finish a one-time task.
    public let finish: Bool

    public init(kind: Kind, id: String, tasks: [TaskItem], title: String, minutes: Int, score: Double,
                reasons: [String], finish: Bool) {
        self.kind = kind
        self.id = id
        self.tasks = tasks
        self.title = title
        self.minutes = minutes
        self.score = score
        self.reasons = reasons
        self.finish = finish
    }
}

/// A check-in about a task that's stalled.
public struct Nudge: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A recurring goal you keep missing: offer a smaller weekly goal.
        case loosen
        /// Untouched for 45+ days: are you serious about it?
        case serious
        /// A high-stakes deadline you haven't worked toward.
        case remind
    }

    public let task: TaskItem
    public let kind: Kind
    public let weight: Double
    /// The smaller weekly goal offered by `.loosen`.
    public let suggest: Int?
    public let text: String
    public let ask: String?

    public var id: String { task.id }
}

/// The next fixed point in today's plan, for "Until 5:00 PM".
public struct Boundary: Equatable, Sendable {
    /// Minutes after midnight.
    public let at: Double
    public let label: String
    public let minutes: Int
}

/// Every calculation the app makes, over a snapshot of the saved state.
/// Ported line for line from the web app so suggestions and plans match.
public struct Engine {
    public let state: PlannerState
    public let now: Date
    public let formats: Formats
    /// The event moved most recently. It wins clashes.
    public var preferredEventID: String?

    public var calendar: Calendar { formats.calendar }

    public init(state: PlannerState, now: Date, formats: Formats, preferredEventID: String? = nil) {
        self.state = state
        self.now = now
        self.formats = formats
        self.preferredEventID = preferredEventID
    }

    public var today: CalendarDay {
        CalendarDay(now, calendar: calendar)
    }

    var nowMinute: Double {
        calendar.minuteOfDay(now)
    }

    // MARK: Task math

    /// Minutes logged on a task in the Monday-to-Sunday week containing `ref`.
    public func weekMinutes(_ taskID: String, ref: Date? = nil) -> Int {
        let start = calendar.mondayOfWeek(containing: ref ?? now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return state.log.reduce(0) { sum, entry in
            entry.taskID == taskID && entry.at >= start && entry.at < end ? sum + entry.minutes : sum
        }
    }

    /// Minutes still to do: this week's goal for recurring goals, otherwise
    /// the estimate minus time spent (never under 5).
    public func remaining(_ task: TaskItem, ref: Date? = nil) -> Int {
        if task.kind == .recurring {
            return max(0, weeklyGoal(task) - weekMinutes(task.id, ref: ref))
        }
        return max(5, estimate(task) - task.spent)
    }

    func weeklyGoal(_ task: TaskItem) -> Int { task.weekly > 0 ? task.weekly : 60 }
    func estimate(_ task: TaskItem) -> Int { task.estimate > 0 ? task.estimate : 30 }
    func errandMinutes(_ task: TaskItem) -> Int { task.estimate > 0 ? task.estimate : 15 }
    func sessionCap(_ task: TaskItem) -> Int { task.maxSession > 0 ? task.maxSession : 45 }
    func blockSize(_ task: TaskItem) -> Int { task.minBlock > 0 ? task.minBlock : 15 }

    /// Doable with the TV on: marked so, or phone-only.
    func tvOK(_ task: TaskItem) -> Bool {
        task.tv || (!task.places.isEmpty && task.places.allSatisfy { $0 == .phone })
    }

    /// Each active task's place within its tier, in list order.
    public func tierPositions() -> [String: (index: Int, count: Int)] {
        var groups: [Int: [TaskItem]] = [:]
        for task in state.activeTasks {
            groups[task.tier, default: []].append(task)
        }
        var positions: [String: (index: Int, count: Int)] = [:]
        for (_, tasks) in groups {
            for (index, task) in tasks.enumerated() {
                positions[task.id] = (index, tasks.count)
            }
        }
        return positions
    }

    public func deadlineLabel(_ day: CalendarDay, ref: Date? = nil) -> String {
        let d = calendar.daysBetween(ref ?? now, day.startDate(calendar: calendar))
        if d < 0 { return d == -1 ? "Overdue since yesterday" : "Overdue by \(-d) days" }
        if d == 0 { return "Due today" }
        if d == 1 { return "Due tomorrow" }
        if d < 7 { return "Due " + formats.weekdayName(day) }
        return "Due " + formats.monthDay(day.startDate(calendar: calendar))
    }

    func daysUntil(_ day: CalendarDay, from ref: Date) -> Int {
        calendar.daysBetween(ref, day.startDate(calendar: calendar))
    }

    /// How strongly to suggest a task, and why.
    public func scoreTask(_ task: TaskItem, context: NowContext?, ref: Date? = nil,
                          position: (index: Int, count: Int)? = nil) -> (score: Double, reasons: [String]) {
        let ref = ref ?? now
        var reasons: [String] = []
        var s = Tier.base(task.tier)
        if let position {
            s += 20 * (1 - Double(position.index) / Double(max(1, position.count)))
        }
        if task.tier == 1 { reasons.append("It’s at the top of your list") }

        if let deadline = task.deadline {
            let d = daysUntil(deadline, from: ref)
            let stakes = Double(task.stakes)
            let urgency: Double = d < 0 ? 95 : d == 0 ? 80 : d == 1 ? 60 : d <= 3 ? 40 : d <= 7 ? 22 : d <= 14 ? 8 : 0
            s += urgency * (0.4 + stakes / 10)
            if urgency >= 22 || (stakes >= 7 && d <= 14) {
                reasons.append(deadlineLabel(deadline, ref: ref) + (stakes >= 7 ? ", and you said you’d be mad if it slipped" : ""))
            }
        }

        if task.kind == .recurring {
            let rem = Double(remaining(task, ref: ref)), goal = Double(weeklyGoal(task))
            s += clamp((rem / goal) * (7 / Double(calendar.daysLeftInWeek(ref))) * 30, 0, 70)
            if rem > 0 { reasons.append("\(TimeText.duration(rem)) left on this week’s \(TimeText.duration(goal)) goal") }
        } else {
            let since = ref.timeIntervalSince(task.lastDone ?? task.created) / 86_400
            s += min(45, max(0, since) * 1.2)
            if since >= 7 {
                reasons.append(task.lastDone != nil
                               ? "You haven’t touched it in \(TimeText.ago(days: since))"
                               : "It’s been on your list for \(TimeText.ago(days: since))")
            }
        }

        if let context {
            if context.posture == .move {
                if task.posture == .move {
                    s += 25
                    reasons.append("Gets you moving")
                } else if task.posture == .sit {
                    s -= 20
                }
            }
            if context.outside == .out && task.outside {
                s += 30
                reasons.append("Gets you outside")
            }
        }
        return (s, reasons)
    }

    /// Whether a task can be done where you are, in the state you're in.
    public func fits(_ task: TaskItem, _ context: NowContext) -> Bool {
        let places = task.places.isEmpty ? [.anywhere] : task.places
        if !places.contains(.anywhere) && !places.contains(context.place) { return false }
        if context.multitasking && task.focus == .deep { return false }
        if context.tv && !tvOK(task) { return false }
        if context.posture == .sit && task.posture == .move { return false }
        if context.outside == .cozy && task.outside { return false }
        return true
    }

    /// How long to work on a task given the time available, or 0 if it won't fit.
    public func sessionMinutes(_ task: TaskItem, available: Int) -> Int {
        let rem = remaining(task)
        let want = task.binge ? rem : min(rem, sessionCap(task))
        let floor = task.kind == .recurring ? min(blockSize(task), want) : min(want, 10)
        if available < floor { return 0 }
        return max(5, min(want, available))
    }

    public func candidate(for task: TaskItem, context: NowContext?, available: Int,
                          position: (index: Int, count: Int)?) -> Candidate? {
        let minutes = sessionMinutes(task, available: available)
        guard minutes > 0 else { return nil }
        var (score, reasons) = scoreTask(task, context: context, ref: now, position: position)
        let finish = task.kind != .recurring && minutes >= remaining(task)
        if finish {
            score += 12
            reasons.append("You can finish it in the time you have")
        } else if task.kind == .recurring {
            reasons.append("A \(TimeText.duration(minutes)) block counts toward this week")
        }
        return Candidate(kind: .task, id: task.id, tasks: [task], title: task.title, minutes: minutes,
                         score: score, reasons: reasons, finish: finish)
    }

    // MARK: The recommender

    /// Suggestions for right now, best first.
    public func recommend(_ context: NowContext, available: Int, skip: Set<String> = []) -> [Candidate] {
        let positions = tierPositions()
        let pool = state.activeTasks.filter { task in
            !skip.contains(task.id) && !(task.snoozeUntil.map { $0 > now } ?? false)
        }
        var out: [Candidate] = []
        for task in pool {
            if task.kind == .errand { continue }
            if task.kind == .recurring && remaining(task) <= 0 { continue }
            if !fits(task, context) { continue }
            if let c = candidate(for: task, context: context, available: available, position: positions[task.id]) {
                out.append(c)
            }
        }

        // Errands are only worth a trip with more than one stop.
        if !context.tv && context.outside != .cozy && (context.place == .home || context.place == .errand) {
            let errands = pool.filter { $0.kind == .errand }
                .map { task -> (task: TaskItem, score: Double, reasons: [String]) in
                    let scored = scoreTask(task, context: context, ref: now, position: positions[task.id])
                    return (task, scored.score, scored.reasons)
                }
                .stableSorted { $0.score > $1.score }
            var picked: [(task: TaskItem, score: Double, reasons: [String])] = []
            var total = 10
            for errand in errands {
                let add = errandMinutes(errand.task) + 10
                if total + add <= available {
                    picked.append(errand)
                    total += add
                }
            }
            if picked.count >= 2 {
                let best = picked.map { $0.score }.max() ?? 0
                out.append(Candidate(kind: .errands, id: "errands", tasks: picked.map { $0.task },
                                     title: "Errand run: \(picked.count) stops", minutes: total,
                                     score: best + 10 * Double(picked.count - 1),
                                     reasons: ["\(picked.count) stops in one trip instead of \(picked.count) trips"] + picked[0].reasons.prefix(2),
                                     finish: false))
            } else if let only = picked.first {
                let daysLeft = only.task.deadline.map { daysUntil($0, from: now) } ?? 99
                if context.place == .errand || daysLeft <= 1 {
                    let lead = context.place == .errand ? "You’re already out" : "Only one stop, but it can’t wait"
                    out.append(Candidate(kind: .task, id: only.task.id, tasks: [only.task], title: only.task.title,
                                         minutes: errandMinutes(only.task) + 20, score: only.score,
                                         reasons: [lead] + only.reasons.prefix(2), finish: true))
                }
            }
        }

        // A block of little things around the house beats one at a time.
        if context.place == .home {
            let small = out.filter { c in
                guard c.kind == .task, let task = c.tasks.first, task.kind == .task else { return false }
                return remaining(task) <= 15 && task.places.contains(.home)
            }
            .stableSorted { $0.score > $1.score }
            var picked: [Candidate] = []
            var total = 0
            for c in small {
                let m = remaining(c.tasks[0])
                if picked.count < 4 && total + m <= available {
                    picked.append(c)
                    total += m
                }
            }
            if picked.count >= 2 {
                let best = picked.map { $0.score }.max() ?? 0
                var reasons = ["A block of small things clears more than picking at them one by one"]
                if context.tv { reasons.append("All doable without leaving the TV room") }
                out.append(Candidate(kind: .sweep, id: "sweep", tasks: picked.map { $0.tasks[0] },
                                     title: "\(picked.count) little things around the house", minutes: total,
                                     score: best + 8 * Double(picked.count - 1), reasons: reasons, finish: false))
            }
        }
        return out.stableSorted { $0.score > $1.score }
    }

    /// The answer to "How much time do you have?" in minutes.
    public func availableMinutes(_ context: NowContext) -> Int {
        if let minutes = context.timeMinutes { return minutes > 0 ? minutes : 30 }
        if let boundary = nextBoundary() { return max(5, boundary.minutes) }
        return 30
    }

    /// The next thing on today's plan at least five minutes away.
    public func nextBoundary() -> Boundary? {
        let plan = planDay(today)
        let n = nowMinute
        var points: [(at: Double, label: String)] = []
        for rock in plan.rocks {
            if rock.start > n {
                points.append((rock.start, "work starts"))
            } else if rock.end > n {
                points.append((rock.end, "work ends"))
            }
        }
        for event in plan.live where event.coreStart > n {
            points.append((event.coreStart, event.travel > 0 ? "leave for \(event.title)" : event.title))
        }
        if let meal = plan.meal, meal.start > n { points.append((meal.start, "dinner")) }
        if plan.bed > n { points.append((plan.bed, "bedtime")) }
        guard let next = points.filter({ $0.at - n >= 5 }).min(by: { $0.at < $1.at }) else { return nil }
        return Boundary(at: next.at, label: next.label, minutes: Int((next.at - n).rounded()))
    }

    // MARK: Check-ins

    public func nudges() -> [Nudge] {
        var out: [Nudge] = []
        for task in state.activeTasks {
            if let until = task.nudgeUntil, until > now { continue }
            let since = now.timeIntervalSince(task.lastDone ?? task.created) / 86_400
            if task.kind == .recurring {
                let age = now.timeIntervalSince(task.created) / 86_400
                if age < 14 { continue }
                let span = min(28, age)
                let from = now.addingTimeInterval(-span * 86_400)
                let minutes = state.log.filter { $0.taskID == task.id && $0.at >= from }.reduce(0) { $0 + $1.minutes }
                let average = Double(minutes) / (span / 7)
                let goal = Double(weeklyGoal(task))
                if average < goal * 0.5 {
                    let basis = average > 0 ? average : goal * 0.4
                    let suggest = max(15, Int((basis / 15).rounded(.up)) * 15)
                    if Double(suggest) < goal {
                        out.append(Nudge(task: task, kind: .loosen, weight: 2 - average / goal, suggest: suggest,
                                         text: "You set \(TimeText.duration(goal)) a week for “\(task.title)”, but you’ve averaged \(TimeText.duration(average)) lately.",
                                         ask: "Loosen the goal, or is this something you’re really serious about?"))
                    }
                }
            } else if since >= 45 {
                out.append(Nudge(task: task, kind: .serious, weight: since / 45, suggest: nil,
                                 text: task.lastDone != nil
                                    ? "You haven’t worked on “\(task.title)” in \(TimeText.ago(days: since))."
                                    : "“\(task.title)” has been on your list for \(TimeText.ago(days: since)) and you haven’t started.",
                                 ask: "Is this something you’re really serious about accomplishing?"))
            } else if let deadline = task.deadline, task.stakes >= 6, since >= 10 {
                let d = daysUntil(deadline, from: now)
                if d >= 0 && d <= 21 {
                    out.append(Nudge(task: task, kind: .remind, weight: 1.5, suggest: nil,
                                     text: "You haven’t worked on “\(task.title)” in \(TimeText.ago(days: since)), and it’s \(deadlineLabel(deadline).lowercased()).",
                                     ask: nil))
                }
            }
        }
        return out.stableSorted { $0.weight > $1.weight }
    }

    // MARK: Banners on the Now screen

    /// Snoozed tasks whose time has come in the last day, at most two.
    public func dueReminders() -> [TaskItem] {
        Array(state.activeTasks.filter { task in
            guard let until = task.snoozeUntil else { return false }
            return until <= now && !task.remindSeen && now.timeIntervalSince(until) < 86_400
        }.prefix(2))
    }

    /// An event you should be leaving for or at right now.
    public func eventNow() -> (event: PlannedEvent, leaveNow: Bool)? {
        let plan = planDay(today)
        let n = nowMinute
        guard let event = plan.live.first(where: { !$0.past && $0.coreStart <= n && n < $0.arrive + $0.stay }) else {
            return nil
        }
        return (event, n < event.arrive)
    }

    /// Minutes of computer work waiting, when it's worth taking to a café.
    public func cafeSuggestion(_ context: NowContext) -> Int? {
        guard state.cafeDismissed != today, context.place == .home || context.place == .computer else { return nil }
        let minutes = state.activeTasks.filter { $0.places.contains(.computer) }.reduce(0) { $0 + remaining($1) }
        let threshold = state.settings.cafeMinutes > 0 ? state.settings.cafeMinutes : 120
        return minutes >= threshold ? minutes : nil
    }
}

func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    max(low, min(high, value))
}

/// Rounds to the nearest 5 minutes, never under 5.
func round5(_ minutes: Double) -> Double {
    max(5, (minutes / 5).rounded() * 5)
}

func overlaps(_ a1: Double, _ a2: Double, _ b1: Double, _ b2: Double) -> Bool {
    a1 < b2 && b1 < a2
}

extension Sequence {
    /// A sort that keeps equal elements in their original order, like JavaScript's.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if areInIncreasingOrder(a.element, b.element) { return true }
            if areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }
        .map(\.element)
    }
}
