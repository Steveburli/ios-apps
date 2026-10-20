import SwiftUI
import Observation
import DoThisNowKit

/// App state: the saved planner, what's on screen, and every action the
/// web app's buttons performed.
@Observable
@MainActor
final class AppModel {
    enum Tab: String { case now, tasks, day }
    enum NowStep { case ask, pick }
    enum PickPanel { case done, later }

    enum Sheet: Identifiable {
        case newTask
        case editTask(String)
        case newEvent(CalendarDay)
        case editEvent(String)
        case settings
        case dayItem(String)
        case meal

        var id: String {
            switch self {
            case .newTask: return "new-task"
            case .editTask(let id): return "task-" + id
            case .newEvent(let day): return "new-event-" + day.key
            case .editEvent(let id): return "event-" + id
            case .settings: return "settings"
            case .dayItem(let id): return "item-" + id
            case .meal: return "meal"
            }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    private(set) var state: PlannerState
    /// Moves forward once a minute, so plans and labels stay current.
    private(set) var now: Date
    var tab: Tab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Keys.tab) }
    }
    var nowStep: NowStep = .ask
    private(set) var picks: [Candidate] = []
    private(set) var pickIndex = 0
    var panel: PickPanel?
    private(set) var available = 60
    var dayShown: CalendarDay
    var moodOpen = false
    var sheet: Sheet?
    private(set) var toast: Toast?
    /// The event moved most recently wins clashes.
    private(set) var lastMovedEventID: String?
    /// Set when the Day tab opens, so the timeline scrolls to now.
    var scrollDayToNow = false

    let formats: Formats
    @ObservationIgnored private var skip: Set<String> = []
    @ObservationIgnored private var drag: (id: String, startArrive: Double, push: Double)?
    @ObservationIgnored private let fileURL: URL

    private enum Keys {
        static let tab = "tab"
    }

    init() {
        let calendar = Calendar.autoupdatingCurrent
        formats = Formats(calendar: calendar)
        let now = Date()
        self.now = now
        dayShown = CalendarDay(now, calendar: calendar)
        tab = Tab(rawValue: UserDefaults.standard.string(forKey: Keys.tab) ?? "") ?? .now

        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("planner.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(PlannerState.self, from: data) {
            state = saved
        } else {
            state = PlannerState()
        }
    }

    var calendar: Calendar { formats.calendar }

    var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    var engine: Engine {
        Engine(state: state, now: now, formats: formats, preferredEventID: lastMovedEventID)
    }

    var currentPick: Candidate? {
        picks.indices.contains(pickIndex) ? picks[pickIndex] : nil
    }

    var morePicks: Int {
        max(0, picks.count - pickIndex - 1)
    }

    // MARK: Saving

    private func commit() {
        state.updatedAt = Date()
        state.prune(now: Date(), calendar: calendar)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            show("Couldn’t save just now. Your change will be saved with the next one.")
        }
        Notifier.sync(state, now: Date())
    }

    func show(_ message: String) {
        toast = Toast(message: message)
    }

    func clearToast(_ id: UUID) {
        if toast?.id == id { toast = nil }
    }

    // MARK: Clock

    /// Called every second while the app is open.
    func tick(_ date: Date = Date()) {
        if Int(date.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) {
            now = date
            if dayShown < today { dayShown = today }
        }
        if var session = state.active, !session.chimed, session.pausedAt == nil, session.isOver(at: date) {
            session.chimed = true
            state.active = session
            if state.settings.sound { Sounds.chime() }
            commit()
        }
    }

    func refreshNow() {
        now = Date()
    }

    // MARK: Now: asking

    func setContext(_ change: (inout NowContext) -> Void) {
        change(&state.context)
        commit()
    }

    /// "Tell me what to do"
    func go() {
        refreshNow()
        available = engine.availableMinutes(state.context)
        skip = []
        refreshPicks()
        nowStep = .pick
    }

    func back() {
        nowStep = .ask
        panel = nil
    }

    private func refreshPicks() {
        picks = engine.recommend(state.context, available: available, skip: skip)
        pickIndex = 0
        panel = nil
    }

    func togglePanel(_ value: PickPanel) {
        panel = panel == value ? nil : value
    }

    // MARK: Now: the pick

    func startCurrentPick() {
        guard let pick = currentPick else { return }
        startSession(tasks: pick.tasks, title: pick.title, minutes: pick.minutes)
    }

    func startSession(tasks: [TaskItem], title: String, minutes: Int) {
        state.startSession(tasks: tasks, title: title, minutes: minutes, at: Date())
        tab = .now
        nowStep = .ask
        panel = nil
        sheet = nil
        Notifier.requestPermission()
        commit()
    }

    func markDone(_ when: DoneWhen) {
        guard let pick = currentPick else { return }
        state.markAlreadyDone(pick, when: when, now: Date())
        refreshPicks()
        commit()
        show(pick.tasks.count > 1 ? "Nice. All crossed off." : "Nice. “\(pick.title)” is crossed off.")
    }

    func snooze(_ choice: SnoozeChoice) {
        guard let pick = currentPick else { return }
        let date = choice.date(from: Date(), wake: state.settings.wake, calendar: calendar)
        state.snooze(pick.tasks.map(\.id), until: date)
        refreshPicks()
        Notifier.requestPermission()
        commit()
        show("I’ll bring it back \(formats.when(date, now: Date()))")
    }

    /// "Just show me something else"
    func skipPick() {
        guard let pick = currentPick else { return }
        skip.formUnion(pick.tasks.map(\.id))
        refreshPicks()
    }

    /// Jumps straight to one task, from a check-in or a reminder.
    func forcePick(_ id: String) {
        guard let task = state.task(id) else { return }
        refreshNow()
        let e = engine
        available = e.availableMinutes(state.context)
        skip = []
        let block = task.minBlock > 0 ? task.minBlock : 15
        let first = e.candidate(for: task, context: nil, available: max(available, block), position: e.tierPositions()[id])
            ?? Candidate(kind: .task, id: id, tasks: [task], title: task.title, minutes: min(e.remaining(task), 30),
                         score: 0, reasons: [], finish: false)
        picks = [first] + e.recommend(state.context, available: available, skip: [id])
        pickIndex = 0
        panel = nil
        nowStep = .pick
        tab = .now
        state.quietNudge(id, days: 7, now: Date())
        commit()
    }

    // MARK: Now: doing

    func pause() {
        state.pauseSession(at: Date())
        commit()
    }

    func resume() {
        state.resumeSession(at: Date())
        commit()
    }

    func extend() {
        state.extendSession()
        commit()
    }

    func endSession(finished: Bool) {
        let message = state.endSession(finished: finished, at: Date())
        nowStep = .ask
        commit()
        if let message { show(message) }
    }

    func cancelSession() {
        state.active = nil
        commit()
        show("Cancelled. Nothing logged.")
    }

    func tick(taskID: String, checked: Bool) {
        state.tick(taskID: taskID, checked: checked, at: Date())
        commit()
    }

    // MARK: Banners and check-ins

    func remindGo(_ id: String) {
        state.clearReminder(id)
        forcePick(id)
    }

    func remindDismiss(_ id: String) {
        state.clearReminder(id)
        commit()
    }

    func cafeDismiss() {
        state.cafeDismissed = today
        commit()
    }

    func cafeGo() {
        state.context.place = .computer
        state.cafeDismissed = today
        commit()
        go()
    }

    func nudgeSerious(_ id: String) {
        if let tier = state.nudgeSerious(id, now: Date()) { show("Moved up to \(Tier.name(tier))") }
        commit()
    }

    func nudgeLower(_ id: String) {
        if let tier = state.nudgeLower(id, now: Date()) { show("Moved down to \(Tier.name(tier))") }
        commit()
    }

    func letGo(_ id: String) {
        let title = state.task(id)?.title ?? ""
        state.letGo(id, now: Date())
        commit()
        show("Let go of “\(title)”")
    }

    func loosen(_ id: String, to weekly: Int) {
        state.loosenGoal(id, to: weekly, now: Date())
        commit()
        show("Goal is now \(TimeText.duration(weekly)) a week")
    }

    func keepGoal(_ id: String) {
        state.quietNudge(id, days: 21, now: Date())
        commit()
        show("Keeping it. I’ll check back in 3 weeks.")
    }

    func remindNextWeek(_ id: String) {
        state.quietNudge(id, days: 7, now: Date())
        commit()
    }

    // MARK: Tasks

    func save(_ task: TaskItem) {
        let isNew = state.task(task.id) == nil
        if isNew {
            state.tasks.append(task)
        } else {
            state.updateTask(task.id) { $0 = task }
        }
        sheet = nil
        if nowStep == .pick { refreshPicks() }
        commit()
        show(isNew ? "Added “\(task.title)”" : "Saved")
    }

    func deleteTask(_ id: String) {
        state.deleteTask(id)
        sheet = nil
        if nowStep == .pick { refreshPicks() }
        commit()
        show("Deleted")
    }

    /// Swipe to cross off a one-time task from the list.
    func markTaskDone(_ id: String) {
        let date = Date()
        state.updateTask(id) { task in
            task.done = true
            task.doneAt = date
            task.lastDone = date
        }
        commit()
        show("Done: “\(state.task(id)?.title ?? "")”")
    }

    func moveTask(_ id: String, toTier tier: Int) {
        state.updateTask(id) { $0.tier = tier }
        commit()
    }

    func restore(_ id: String) {
        state.restore(id, now: Date())
        commit()
    }

    func applyOrder(_ rows: [(id: String, tier: Int)]) {
        state.applyOrder(rows)
        commit()
    }

    func loadExamples() {
        state.loadExamples(now: Date(), calendar: calendar)
        sheet = nil
        commit()
        show("Loaded example tasks")
    }

    func removeExamples() {
        state.removeExamples()
        nowStep = .ask
        sheet = nil
        commit()
        show("Examples removed")
    }

    func eraseEverything() {
        state.eraseEverything()
        nowStep = .ask
        sheet = nil
        commit()
        show("Everything erased")
    }

    func saveSettings(_ settings: PlannerSettings) {
        state.settings = settings
        sheet = nil
        commit()
        show("Settings saved")
    }

    // MARK: Day

    func showDay(offset: Int) {
        let target = dayShown.adding(days: offset, calendar: calendar)
        let distance = today.days(until: target, calendar: calendar)
        guard (0...13).contains(distance) else { return }
        dayShown = target
    }

    func openDayTab() {
        refreshNow()
        dayShown = today
        scrollDayToNow = true
    }

    func save(_ event: PlannerEvent) {
        let isNew = !state.events.contains { $0.id == event.id }
        if isNew {
            state.events.append(event)
        } else if let index = state.events.firstIndex(where: { $0.id == event.id }) {
            state.events[index] = event
        }
        lastMovedEventID = event.id
        sheet = nil
        commit()
        show(isNew ? "Added “\(event.title)”" : "Saved")
    }

    func deleteEvent(_ id: String) {
        state.deleteEvent(id)
        sheet = nil
        commit()
        show("Event deleted")
    }

    func setDinner(_ mode: DinnerMode) {
        state.updateDay(dayShown) { $0.dinner = mode }
        sheet = nil
        commit()
        show("Dinner: \(mode.label.lowercased())")
    }

    /// The chunk (and its pieces) behind a block on the Day view.
    func chunk(_ id: String, in plan: DayPlan) -> Chunk? {
        plan.items.first { $0.chunk.id == id }?.chunk ?? plan.ghosts.first { $0.chunk.id == id }?.chunk
    }

    func startFromDay(_ id: String) {
        guard let chunk = chunk(id, in: engine.planDay(dayShown)) else { return }
        startSession(tasks: chunk.tasks, title: chunk.title, minutes: Int(chunk.minutes.rounded()))
    }

    func toggleMust(_ id: String) {
        let before = engine.planDay(dayShown)
        guard let chunk = chunk(id, in: before) else { return }
        let ids = chunk.tasks.map(\.id)
        state.updateDay(dayShown) { config in
            var must = Set(config.must)
            let on = ids.contains { must.contains($0) }
            for taskID in ids {
                if on { must.remove(taskID) } else { must.insert(taskID) }
            }
            config.must = Array(must)
        }
        sheet = nil
        commit()
        let after = engine.planDay(dayShown).push
        if after > before.push + 4 && state.settings.sound { Sounds.groan(push: after) }
    }

    func skipForDay(_ id: String) {
        guard let chunk = chunk(id, in: engine.planDay(dayShown)) else { return }
        let ids = Set(chunk.tasks.map(\.id))
        state.updateDay(dayShown) { config in
            config.skip = Array(Set(config.skip).union(ids))
            config.must.removeAll { ids.contains($0) }
        }
        sheet = nil
        commit()
        show("Taken off this day")
    }

    func unskip(_ taskID: String) {
        state.updateDay(dayShown) { $0.skip.removeAll { $0 == taskID } }
        commit()
    }

    /// Dragging an event's solid core sets when you arrive.
    func dragArrival(of event: PlannedEvent, by points: CGFloat, pointsPerMinute: CGFloat) {
        if drag?.id != event.id {
            drag = (event.id, event.arrive, engine.planDay(dayShown).push)
        }
        guard let drag else { return }
        let low = event.winStart, high = event.winEnd - event.stay
        let raw = drag.startArrive + Double(points / pointsPerMinute)
        let minute = max(low, min(high, (raw / 5).rounded() * 5))
        setArrival(event.id, minute: minute, windowStart: low)
    }

    func endArrivalDrag() {
        guard let drag else { return }
        self.drag = nil
        commit()
        let push = engine.planDay(dayShown).push
        if push > drag.push + 4 && state.settings.sound { Sounds.groan(push: push) }
    }

    /// VoiceOver's swipe up and down on an event, five minutes at a time.
    func nudgeArrival(of event: PlannedEvent, by minutes: Double) {
        let low = event.winStart, high = event.winEnd - event.stay
        setArrival(event.id, minute: max(low, min(high, event.arrive + minutes)), windowStart: low)
        commit()
    }

    private func setArrival(_ id: String, minute: Double, windowStart: Double) {
        guard let index = state.events.firstIndex(where: { $0.id == id }) else { return }
        let value: Int? = minute <= windowStart ? nil : Int(minute.rounded())
        if state.events[index].arrive != value { state.events[index].arrive = value }
        lastMovedEventID = id
    }
}
