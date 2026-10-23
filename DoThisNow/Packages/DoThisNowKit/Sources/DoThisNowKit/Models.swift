import Foundation

// Everything decodes field by field with defaults, so a saved file from an
// older version still loads after new fields are added.

public enum TaskKind: String, Codable, CaseIterable, Sendable {
    case task, recurring, errand
}

/// Where a task can be done, and where the person is right now.
public enum Place: String, Codable, CaseIterable, Sendable {
    case home, phone, computer, office, errand, anywhere

    public var label: String {
        switch self {
        case .home: return "At home"
        case .phone: return "On my phone"
        case .computer: return "On my computer"
        case .office: return "At the office"
        case .errand: return "Out and about"
        case .anywhere: return "Anywhere"
        }
    }

    public var shortLabel: String {
        switch self {
        case .home: return "Home"
        case .phone: return "Phone"
        case .computer: return "Computer"
        case .office: return "Office"
        case .errand: return "Errand"
        case .anywhere: return "Anywhere"
        }
    }

    /// The choices for "Where are you doing your work?"
    public static let current: [Place] = [.home, .phone, .computer, .office, .errand]
    /// The choices for "Where can you do it?"
    public static let taskPlaces: [Place] = [.home, .computer, .phone, .office, .anywhere]
}

public enum FocusLevel: String, Codable, Sendable {
    case deep, light
}

public enum Posture: String, Codable, Sendable {
    case sit, move, any
}

public enum OutsidePreference: String, Codable, Sendable {
    case any, out, cozy
}

public enum Tier {
    public static let all = [1, 2, 3, 4]

    public static func name(_ tier: Int) -> String {
        switch tier {
        case 1: return "Top priority"
        case 2: return "High"
        case 3: return "Medium"
        default: return "Someday"
        }
    }

    static func base(_ tier: Int) -> Double {
        switch tier {
        case 1: return 400
        case 2: return 300
        case 3: return 200
        case 4: return 100
        default: return 200
        }
    }
}

public enum DinnerMode: String, Codable, CaseIterable, Sendable {
    case full, oven, fast, micro, none

    public var label: String {
        switch self {
        case .full: return "Make a full dinner"
        case .oven: return "Heat something up in the oven"
        case .fast: return "Fast food"
        case .micro: return "Microwave"
        case .none: return "No dinner block (eating out)"
        }
    }

    public var minutes: Int {
        switch self {
        case .full: return 60
        case .oven: return 35
        case .fast: return 25
        case .micro: return 10
        case .none: return 0
        }
    }
}

/// How mad you'd be if a deadline slipped, 0–10.
public func stakesLabel(_ value: Int) -> String {
    switch value {
    case ...1: return "Shrug"
    case ...3: return "Mildly annoyed"
    case ...5: return "Annoyed"
    case ...7: return "Pretty mad"
    case ...9: return "Really mad"
    default: return "Furious"
    }
}

public func newID() -> String {
    UUID().uuidString.lowercased()
}

// MARK: - Tasks

public struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: TaskKind = .task
    /// 1 (top) to 4 (someday).
    public var tier: Int = 3
    /// Where it can be done ("where" in the web app).
    public var places: [Place] = [.home]
    /// Minutes, start to finish (one-time tasks and errands).
    public var estimate: Int = 30
    /// Minutes a week (recurring goals).
    public var weekly: Int = 120
    /// Smallest useful block (recurring goals).
    public var minBlock: Int = 15
    /// Store name or address (errands).
    public var place: String = ""
    public var deadline: CalendarDay?
    public var stakes: Int = 5
    public var binge: Bool = false
    public var maxSession: Int = 45
    public var focus: FocusLevel = .light
    public var posture: Posture = .any
    public var outside: Bool = false
    public var tv: Bool = false
    public var notes: String = ""
    public var isExample: Bool = false
    public var created: Date
    /// Minutes logged so far (one-time tasks).
    public var spent: Int = 0
    public var lastDone: Date?
    public var done: Bool = false
    public var doneAt: Date?
    public var archived: Bool = false
    public var snoozeUntil: Date?
    public var remindSeen: Bool = false
    public var nudgeUntil: Date?

    public init(id: String = newID(), title: String, created: Date) {
        self.id = id
        self.title = title
        self.created = created
    }

    public var isActive: Bool {
        !done && !archived
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, tier, places, estimate, weekly, minBlock, place, deadline, stakes, binge,
             maxSession, focus, posture, outside, tv, notes, isExample, created, spent, lastDone, done,
             doneAt, archived, snoozeUntil, remindSeen, nudgeUntil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  created: try c.decodeIfPresent(Date.self, forKey: .created) ?? Date())
        kind = try c.decodeIfPresent(TaskKind.self, forKey: .kind) ?? kind
        tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? tier
        places = try c.decodeIfPresent([Place].self, forKey: .places) ?? places
        estimate = try c.decodeIfPresent(Int.self, forKey: .estimate) ?? estimate
        weekly = try c.decodeIfPresent(Int.self, forKey: .weekly) ?? weekly
        minBlock = try c.decodeIfPresent(Int.self, forKey: .minBlock) ?? minBlock
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? place
        deadline = try c.decodeIfPresent(CalendarDay.self, forKey: .deadline)
        stakes = try c.decodeIfPresent(Int.self, forKey: .stakes) ?? stakes
        binge = try c.decodeIfPresent(Bool.self, forKey: .binge) ?? binge
        maxSession = try c.decodeIfPresent(Int.self, forKey: .maxSession) ?? maxSession
        focus = try c.decodeIfPresent(FocusLevel.self, forKey: .focus) ?? focus
        posture = try c.decodeIfPresent(Posture.self, forKey: .posture) ?? posture
        outside = try c.decodeIfPresent(Bool.self, forKey: .outside) ?? outside
        tv = try c.decodeIfPresent(Bool.self, forKey: .tv) ?? tv
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? notes
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? isExample
        spent = try c.decodeIfPresent(Int.self, forKey: .spent) ?? spent
        lastDone = try c.decodeIfPresent(Date.self, forKey: .lastDone)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? done
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? archived
        snoozeUntil = try c.decodeIfPresent(Date.self, forKey: .snoozeUntil)
        remindSeen = try c.decodeIfPresent(Bool.self, forKey: .remindSeen) ?? remindSeen
        nudgeUntil = try c.decodeIfPresent(Date.self, forKey: .nudgeUntil)
    }
}

// MARK: - Events

/// Something with a time window. You pick when to arrive inside the window,
/// and the minimum stay plus travel is the part that can't be squeezed.
public struct PlannerEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var day: CalendarDay
    /// Minutes after midnight.
    public var start: Int
    public var end: Int
    public var minStay: Int
    /// Minutes each way.
    public var travel: Int
    /// Minutes after midnight; nil means "at the start".
    public var arrive: Int?
    /// Take time off work if it overlaps.
    public var overWork: Bool
    public var isExample: Bool

    public init(id: String = newID(), title: String, day: CalendarDay, start: Int, end: Int, minStay: Int,
                travel: Int, arrive: Int? = nil, overWork: Bool = false, isExample: Bool = false) {
        self.id = id
        self.title = title
        self.day = day
        self.start = start
        self.end = end
        self.minStay = minStay
        self.travel = travel
        self.arrive = arrive
        self.overWork = overWork
        self.isExample = isExample
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, day, start, end, minStay, travel, arrive, overWork, isExample
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  day: try c.decode(CalendarDay.self, forKey: .day),
                  start: try c.decodeIfPresent(Int.self, forKey: .start) ?? 18 * 60,
                  end: try c.decodeIfPresent(Int.self, forKey: .end) ?? 19 * 60,
                  minStay: try c.decodeIfPresent(Int.self, forKey: .minStay) ?? 60,
                  travel: try c.decodeIfPresent(Int.self, forKey: .travel) ?? 0,
                  arrive: try c.decodeIfPresent(Int.self, forKey: .arrive),
                  overWork: try c.decodeIfPresent(Bool.self, forKey: .overWork) ?? false,
                  isExample: try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false)
    }
}

/// Time spent on a task.
public struct LogEntry: Codable, Equatable, Sendable {
    public var taskID: String
    public var at: Date
    public var minutes: Int

    public init(taskID: String, at: Date, minutes: Int) {
        self.taskID = taskID
        self.at = at
        self.minutes = minutes
    }
}

// MARK: - Settings and preferences

public struct WorkHours: Codable, Equatable, Sendable {
    public var on = true
    /// 0 = Sunday … 6 = Saturday.
    public var days: [Int] = [1, 2, 3, 4, 5]
    public var start = 9 * 60
    public var end = 17 * 60

    public init() {}

    private enum CodingKeys: String, CodingKey { case on, days, start, end }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? on
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? days
        start = try c.decodeIfPresent(Int.self, forKey: .start) ?? start
        end = try c.decodeIfPresent(Int.self, forKey: .end) ?? end
    }
}

public struct PlannerSettings: Codable, Equatable, Sendable {
    /// Minutes after midnight.
    public var wake = 7 * 60
    public var bed = 23 * 60
    public var dinnerAt = 18 * 60 + 30
    public var dinner: DinnerMode = .oven
    public var work = WorkHours()
    /// Suggest a coffee shop once this much computer work piles up.
    public var cafeMinutes = 120
    public var sound = true
    /// Suggest tasks for the gaps between the blocks you placed yourself.
    public var autoFill = true

    public init() {}

    private enum CodingKeys: String, CodingKey { case wake, bed, dinnerAt, dinner, work, cafeMinutes, sound, autoFill }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wake = try c.decodeIfPresent(Int.self, forKey: .wake) ?? wake
        bed = try c.decodeIfPresent(Int.self, forKey: .bed) ?? bed
        dinnerAt = try c.decodeIfPresent(Int.self, forKey: .dinnerAt) ?? dinnerAt
        dinner = try c.decodeIfPresent(DinnerMode.self, forKey: .dinner) ?? dinner
        work = try c.decodeIfPresent(WorkHours.self, forKey: .work) ?? work
        cafeMinutes = try c.decodeIfPresent(Int.self, forKey: .cafeMinutes) ?? cafeMinutes
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? sound
        autoFill = try c.decodeIfPresent(Bool.self, forKey: .autoFill) ?? autoFill
    }
}

/// The answers on the Now screen.
public struct NowContext: Codable, Equatable, Sendable {
    /// nil means "until the next thing on my day".
    public var timeMinutes: Int?
    public var place: Place = .home
    public var multitasking = false
    public var tv = false
    public var posture: Posture = .any
    public var outside: OutsidePreference = .any

    public init() {}

    private enum CodingKeys: String, CodingKey { case timeMinutes, place, multitasking, tv, posture, outside }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeMinutes = try c.decodeIfPresent(Int.self, forKey: .timeMinutes)
        place = try c.decodeIfPresent(Place.self, forKey: .place) ?? place
        multitasking = try c.decodeIfPresent(Bool.self, forKey: .multitasking) ?? multitasking
        tv = try c.decodeIfPresent(Bool.self, forKey: .tv) ?? tv
        posture = try c.decodeIfPresent(Posture.self, forKey: .posture) ?? posture
        outside = try c.decodeIfPresent(OutsidePreference.self, forKey: .outside) ?? outside
    }
}

/// Per-day overrides on the Day view.
public struct DayConfig: Codable, Equatable, Sendable {
    /// Task IDs set aside for the day.
    public var skip: [String] = []
    /// Task IDs that must happen that day.
    public var must: [String] = []
    public var dinner: DinnerMode?
    public var noWork = false

    public init() {}

    private enum CodingKeys: String, CodingKey { case skip, must, dinner, noWork }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skip = try c.decodeIfPresent([String].self, forKey: .skip) ?? []
        must = try c.decodeIfPresent([String].self, forKey: .must) ?? []
        dinner = try c.decodeIfPresent(DinnerMode.self, forKey: .dinner)
        noWork = try c.decodeIfPresent(Bool.self, forKey: .noWork) ?? false
    }
}

/// The timer that runs while you work on something.
public struct ActiveSession: Codable, Equatable, Sendable {
    public var taskIDs: [String]
    public var title: String
    /// Planned minutes.
    public var planned: Int
    public var startedAt: Date
    public var pausedAt: Date?
    /// Seconds spent paused so far.
    public var pausedSeconds: TimeInterval = 0
    /// Several small things or an errand run, shown as a checklist.
    public var bundle: Bool
    public var ticked: [String] = []
    public var chimed = false
    /// The block on the Day it was started from.
    public var blockID: String?
    /// The task it's for, when it isn't one of Do This Now's own.
    public var ref: SourceRef?

    public init(taskIDs: [String], title: String, planned: Int, startedAt: Date, bundle: Bool) {
        self.taskIDs = taskIDs
        self.title = title
        self.planned = planned
        self.startedAt = startedAt
        self.bundle = bundle
    }

    public func elapsed(at now: Date) -> TimeInterval {
        (pausedAt ?? now).timeIntervalSince(startedAt) - pausedSeconds
    }

    /// When the planned time runs out, or nil while paused.
    public var endsAt: Date? {
        guard pausedAt == nil else { return nil }
        return startedAt.addingTimeInterval(pausedSeconds + TimeInterval(planned * 60))
    }

    public func isOver(at now: Date) -> Bool {
        elapsed(at: now) >= TimeInterval(planned * 60)
    }
}

// MARK: - The whole saved state

public struct PlannerState: Codable, Equatable, Sendable {
    public var tasks: [TaskItem] = []
    public var events: [PlannerEvent] = []
    public var log: [LogEntry] = []
    /// Day key → overrides.
    public var days: [String: DayConfig] = [:]
    public var settings = PlannerSettings()
    public var context = NowContext()
    /// The day the coffee-shop suggestion was dismissed.
    public var cafeDismissed: CalendarDay?
    public var active: ActiveSession?
    /// Tasks you put on a day yourself.
    public var blocks: [TimeBlock] = []
    /// Tasks typed into the Inbox or sent by Shortcuts.
    public var inboxItems: [InboxItem] = []
    public var inbox = InboxSettings()
    /// The Track tab: things you time, their timings, and the stopwatch.
    public var activities: [Activity] = []
    public var timings: [Timing] = []
    public var running: RunningTimer?
    public var wake = WakeSettings()
    public var updatedAt = Date(timeIntervalSince1970: 0)

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case tasks, events, log, days, settings, context, cafeDismissed, active, blocks, inboxItems, inbox,
             activities, timings, running, wake, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        events = try c.decodeIfPresent([PlannerEvent].self, forKey: .events) ?? []
        log = try c.decodeIfPresent([LogEntry].self, forKey: .log) ?? []
        days = try c.decodeIfPresent([String: DayConfig].self, forKey: .days) ?? [:]
        settings = try c.decodeIfPresent(PlannerSettings.self, forKey: .settings) ?? PlannerSettings()
        context = try c.decodeIfPresent(NowContext.self, forKey: .context) ?? NowContext()
        cafeDismissed = try c.decodeIfPresent(CalendarDay.self, forKey: .cafeDismissed)
        active = try c.decodeIfPresent(ActiveSession.self, forKey: .active)
        blocks = try c.decodeIfPresent([TimeBlock].self, forKey: .blocks) ?? []
        inboxItems = try c.decodeIfPresent([InboxItem].self, forKey: .inboxItems) ?? []
        inbox = try c.decodeIfPresent(InboxSettings.self, forKey: .inbox) ?? InboxSettings()
        activities = try c.decodeIfPresent([Activity].self, forKey: .activities) ?? []
        timings = try c.decodeIfPresent([Timing].self, forKey: .timings) ?? []
        running = try c.decodeIfPresent(RunningTimer.self, forKey: .running)
        wake = try c.decodeIfPresent(WakeSettings.self, forKey: .wake) ?? WakeSettings()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    public var activeTasks: [TaskItem] {
        tasks.filter(\.isActive)
    }

    public var hasExamples: Bool {
        tasks.contains(where: \.isExample) || events.contains(where: \.isExample)
    }

    public func task(_ id: String) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    public mutating func updateTask(_ id: String, _ change: (inout TaskItem) -> Void) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            change(&tasks[index])
        }
    }

    public func dayConfig(_ day: CalendarDay) -> DayConfig {
        days[day.key] ?? DayConfig()
    }

    public mutating func updateDay(_ day: CalendarDay, _ change: (inout DayConfig) -> Void) {
        var config = days[day.key] ?? DayConfig()
        change(&config)
        days[day.key] = config
    }

    /// Keeps the saved file small: 150 days of log, a year of timings, 250
    /// finished tasks, no past day settings, events and blocks from the last
    /// two weeks on, and finished Inbox items from the last month.
    public mutating func prune(now: Date, calendar: Calendar) {
        let cutoff = now.addingTimeInterval(-150 * 86_400)
        log = Array(log.filter { $0.at >= cutoff }.suffix(1500))
        let timingCutoff = now.addingTimeInterval(-365 * 86_400)
        timings = Array(timings.filter { $0.start >= timingCutoff }.suffix(3000))
        let inboxCutoff = now.addingTimeInterval(-30 * 86_400)
        inboxItems.removeAll { $0.done && ($0.doneAt ?? $0.created) < inboxCutoff }

        let finished = tasks.filter { !$0.isActive }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        if finished.count > 250 {
            let drop = Set(finished.dropFirst(250).map(\.id))
            tasks.removeAll { drop.contains($0.id) }
        }

        let today = CalendarDay(now, calendar: calendar)
        days = days.filter { key, _ in
            guard let day = CalendarDay(key: key) else { return false }
            return day >= today
        }
        let eventCutoff = today.adding(days: -14, calendar: calendar)
        events.removeAll { $0.day < eventCutoff }
        blocks.removeAll { $0.day < eventCutoff }
    }
}
