import Foundation

/// A task typed into the Inbox, or sent by Shortcuts or the Share button.
public struct InboxItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var notes = ""
    /// How long it'll take, when whoever sent it said.
    public var minutes: Int?
    public var created: Date
    public var done = false
    public var doneAt: Date?
    public var isExample = false

    public init(id: String = newID(), title: String, notes: String = "", minutes: Int? = nil, created: Date) {
        self.id = id
        self.title = title
        self.notes = notes
        self.minutes = minutes
        self.created = created
    }

    private enum CodingKeys: String, CodingKey { case id, title, notes, minutes, created, done, doneAt, isExample }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  notes: try c.decodeIfPresent(String.self, forKey: .notes) ?? "",
                  minutes: try c.decodeIfPresent(Int.self, forKey: .minutes),
                  created: try c.decodeIfPresent(Date.self, forKey: .created) ?? Date())
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
    }
}

/// One task from any source, the way the Inbox sees it.
public struct SourceTask: Identifiable, Equatable, Sendable {
    public var ref: SourceRef
    public var title: String
    public var notes: String
    /// The list it's in: a Reminders list, a Google task list, or a priority level.
    public var listID: String
    public var listName: String
    public var due: Date?
    /// 0 none, 1 low, 2 medium, 3 high.
    public var priority: Int
    /// The source's own estimate, if it has one.
    public var minutes: Int?

    public init(ref: SourceRef, title: String, notes: String = "", listID: String = "", listName: String = "",
                due: Date? = nil, priority: Int = 0, minutes: Int? = nil) {
        self.ref = ref
        self.title = title
        self.notes = notes
        self.listID = listID
        self.listName = listName
        self.due = due
        self.priority = priority
        self.minutes = minutes
    }

    public var id: String {
        ref.key
    }
}

/// How soon something has to be due to come into the Inbox.
public enum DueWindow: String, Codable, CaseIterable, Sendable {
    case any, today, threeDays, week

    public var label: String {
        switch self {
        case .any: return "Any time"
        case .today: return "Today or overdue"
        case .threeDays: return "Within 3 days"
        case .week: return "Within a week"
        }
    }

    /// The last day that counts, as days from today.
    var days: Int? {
        switch self {
        case .any: return nil
        case .today: return 0
        case .threeDays: return 2
        case .week: return 6
        }
    }
}

/// Which tasks from one source come into the Inbox.
public struct SourceFilter: Codable, Equatable, Sendable {
    public var on: Bool
    /// Lists to leave out.
    public var hiddenLists: [String] = []
    public var due: DueWindow = .any
    /// Let in tasks with no due date.
    public var undated = true
    /// 0 lets everything in; 3 only high priority.
    public var minPriority = 0
    /// When set, only tasks with this word in the title or notes.
    public var keyword = ""

    public init(on: Bool, hiddenLists: [String] = []) {
        self.on = on
        self.hiddenLists = hiddenLists
    }

    private enum CodingKeys: String, CodingKey { case on, hiddenLists, due, undated, minPriority, keyword }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? true
        hiddenLists = try c.decodeIfPresent([String].self, forKey: .hiddenLists) ?? []
        due = try c.decodeIfPresent(DueWindow.self, forKey: .due) ?? .any
        undated = try c.decodeIfPresent(Bool.self, forKey: .undated) ?? true
        minPriority = try c.decodeIfPresent(Int.self, forKey: .minPriority) ?? 0
        keyword = try c.decodeIfPresent(String.self, forKey: .keyword) ?? ""
    }

    public func allows(_ task: SourceTask, today: CalendarDay, calendar: Calendar) -> Bool {
        if hiddenLists.contains(task.listID) { return false }
        if task.priority < minPriority { return false }
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !word.isEmpty && !task.title.localizedCaseInsensitiveContains(word) && !task.notes.localizedCaseInsensitiveContains(word) {
            return false
        }
        guard let due = task.due else { return undated }
        guard let days = self.due.days else { return true }
        return today.days(until: CalendarDay(due, calendar: calendar), calendar: calendar) <= days
    }
}

/// Where the Inbox gets tasks, and your choices about them.
public struct InboxSettings: Codable, Equatable, Sendable {
    /// Someday tasks stay out unless you ask for them.
    public var app = SourceFilter(on: true, hiddenLists: ["tier-4"])
    public var reminders = SourceFilter(on: false)
    public var google = SourceFilter(on: false)
    public var inbox = SourceFilter(on: true)
    /// Tasks you swiped away, by source key.
    public var hidden: [String] = []
    /// Minutes you set by hand, by source key.
    public var minutes: [String: Int] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case app, reminders, google, inbox, hidden, minutes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(SourceFilter.self, forKey: .app) ?? app
        reminders = try c.decodeIfPresent(SourceFilter.self, forKey: .reminders) ?? reminders
        google = try c.decodeIfPresent(SourceFilter.self, forKey: .google) ?? google
        inbox = try c.decodeIfPresent(SourceFilter.self, forKey: .inbox) ?? inbox
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
        minutes = try c.decodeIfPresent([String: Int].self, forKey: .minutes) ?? [:]
    }

    public subscript(source: TaskSource) -> SourceFilter {
        get {
            switch source {
            case .app: return app
            case .reminders: return reminders
            case .google: return google
            case .inbox: return inbox
            }
        }
        set {
            switch source {
            case .app: app = newValue
            case .reminders: reminders = newValue
            case .google: google = newValue
            case .inbox: inbox = newValue
            }
        }
    }
}

/// A row in the Inbox: the task and how long it should take.
public struct InboxEntry: Identifiable, Equatable, Sendable {
    public let task: SourceTask
    public let estimate: Estimate

    public var id: String {
        task.id
    }
}

extension Engine {
    /// Do This Now's own tasks, as the Inbox sees them. Their priority level
    /// is their "list", so whole levels can be left out.
    public func appSourceTasks() -> [SourceTask] {
        state.activeTasks.compactMap { task in
            if let until = task.snoozeUntil, until > now { return nil }
            let minutes: Int
            switch task.kind {
            case .recurring:
                let left = remaining(task)
                if left <= 0 { return nil }
                minutes = min(left, sessionCap(task))
            case .errand:
                minutes = errandMinutes(task) + 20
            case .task:
                minutes = remaining(task)
            }
            return SourceTask(ref: SourceRef(.app, task.id), title: task.title, notes: task.notes,
                              listID: "tier-\(task.tier)", listName: Tier.name(task.tier),
                              due: task.deadline?.startDate(calendar: calendar), priority: max(0, 4 - task.tier),
                              minutes: minutes)
        }
    }

    /// The Inbox's own items, as the Inbox sees them.
    public func inboxSourceTasks() -> [SourceTask] {
        state.inboxItems.filter { !$0.done }.map { item in
            SourceTask(ref: SourceRef(.inbox, item.id), title: item.title, notes: item.notes,
                       listID: "inbox", listName: "Inbox", minutes: item.minutes)
        }
    }

    /// What the Inbox shows: tasks from every source that's on, through that
    /// source's filters, minus what you swiped away and what's already on a
    /// day. Soonest due first, then highest priority.
    public func inbox(external: [SourceTask]) -> [InboxEntry] {
        let settings = state.inbox
        let hidden = Set(settings.hidden)
        let planned = state.plannedKeys(from: today)
        let all = appSourceTasks() + inboxSourceTasks() + external
        let kept = all.filter { task in
            let filter = settings[task.ref.source]
            return filter.on && !hidden.contains(task.id) && !planned.contains(task.id)
                && filter.allows(task, today: today, calendar: calendar)
        }
        return kept
            .stableSorted { a, b in
                switch (a.due, b.due) {
                case let (x?, y?) where calendar.daysBetween(x, y) != 0: return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                default: return a.priority > b.priority
                }
            }
            .map { InboxEntry(task: $0, estimate: estimate(for: $0)) }
    }

    public func estimate(for task: SourceTask) -> Estimate {
        state.estimate(title: task.title, custom: state.inbox.minutes[task.id], source: task.minutes)
    }
}
