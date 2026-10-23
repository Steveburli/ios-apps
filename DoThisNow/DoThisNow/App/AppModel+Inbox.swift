import SwiftUI
import DoThisNowKit

/// The Inbox and the blocks you place on the Day yourself.
extension AppModel {
    // MARK: Sources

    /// Everything the Inbox shows right now, through your filters.
    var inboxEntries: [InboxEntry] {
        engine.inbox(external: reminderTasks + googleTasks)
    }

    func inboxEntry(_ key: String) -> InboxEntry? {
        inboxEntries.first { $0.id == key }
    }

    /// Reads Reminders and Google Tasks again, for the sources that are on.
    func refreshSources() async {
        guard !Screenshots.isActive else { return }
        let reminders = RemindersSource.shared
        if reminders.isAuthorized {
            reminderLists = reminders.lists()
            reminderTasks = state.inbox.reminders.on ? await reminders.fetch() : []
            sourceProblem[.reminders] = nil
        } else {
            reminderTasks = []
            reminderLists = []
        }

        let google = GoogleTasks.shared
        googleSignedIn = google.isSignedIn
        if googleSignedIn {
            do {
                let lists = try await google.lists()
                googleLists = lists
                googleTasks = state.inbox.google.on ? try await google.tasks(in: lists) : []
                sourceProblem[.google] = nil
            } catch {
                sourceProblem[.google] = "Couldn’t reach Google Tasks: \(error.localizedDescription)"
                googleSignedIn = google.isSignedIn
            }
        } else {
            googleTasks = []
            googleLists = []
        }
    }

    /// Asks for Reminders access the first time, then turns the source on.
    func connectReminders() async {
        let granted = await RemindersSource.shared.requestAccess()
        if granted {
            state.inbox.reminders.on = true
            commit()
            await refreshSources()
        } else {
            sourceProblem[.reminders] = "Do This Now can’t see your reminders. Turn on Reminders for Do This Now in the Settings app, under Apps."
        }
    }

    func connectGoogle() async {
        do {
            try await GoogleTasks.shared.signIn()
            googleSignedIn = true
            state.inbox.google.on = true
            commit()
            await refreshSources()
        } catch GoogleTasks.Failure.cancelled {
            // Closed the sign-in sheet.
        } catch {
            sourceProblem[.google] = "Google sign-in didn’t finish: \(error.localizedDescription)"
        }
    }

    func disconnectGoogle() {
        GoogleTasks.shared.signOut()
        googleSignedIn = false
        googleTasks = []
        googleLists = []
        state.inbox.google.on = false
        commit()
    }

    /// Whether the Day fills the gaps between your blocks with suggestions.
    func setAutoFill(_ on: Bool) {
        state.settings.autoFill = on
        commit()
    }

    func setFilter(_ source: TaskSource, _ change: (inout SourceFilter) -> Void) {
        change(&state.inbox[source])
        commit()
        Task { await refreshSources() }
    }

    /// Tasks sent by Shortcuts or the Share button while the app was closed.
    func takeDroppedTasks() {
        let drops = InboxDropbox.take()
        guard !drops.isEmpty else { return }
        for drop in drops {
            state.inboxItems.append(InboxItem(title: drop.title, notes: drop.notes, minutes: drop.minutes, created: drop.at))
        }
        commit()
        if drops.count == 1, let drop = drops.first {
            show("“\(drop.title)” is in your Inbox")
        } else {
            show("\(drops.count) new tasks in your Inbox")
        }
    }

    // MARK: The Inbox

    func addToInbox(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.inboxItems.append(InboxItem(title: trimmed, created: Date()))
        commit()
    }

    /// Minutes you set yourself, or nil to go back to the estimate.
    func setMinutes(_ key: String, _ minutes: Int?) {
        if let minutes {
            state.inbox.minutes[key] = minutes
        } else {
            state.inbox.minutes.removeValue(forKey: key)
        }
        commit()
    }

    func hideFromInbox(_ key: String) {
        if !state.inbox.hidden.contains(key) { state.inbox.hidden.append(key) }
        sheet = nil
        commit()
        show("Hidden from the Inbox. Inbox settings can bring it back.")
    }

    func unhideAll() {
        state.inbox.hidden = []
        commit()
        show("Everything you hid is back in the Inbox")
    }

    /// Puts an Inbox task on a day at `minute`, bumping whatever it lands on.
    func schedule(_ key: String, at minute: Int, on day: CalendarDay, minutes: Int? = nil) {
        guard let entry = inboxEntry(key) else { return }
        let block = TimeBlock(ref: entry.task.ref, title: entry.task.title, day: day, start: max(0, minute),
                              minutes: minutes ?? entry.estimate.minutes)
        state.blocks.append(block)
        state.blocks = reflowed(state.blocks, moving: block.id, to: block.start, day: day)
        draggingKey = nil
        sheet = nil
        dayShown = day
        commit()
        show("“\(block.title)” at \(formats.time(day, Double(state.block(block.id)?.start ?? block.start)))")
    }

    func scheduleInNextGap(_ key: String, on day: CalendarDay) {
        guard let entry = inboxEntry(key) else { return }
        if let start = openSlots(on: day, minutes: entry.estimate.minutes, limit: 1).first {
            schedule(key, at: start, on: day)
        } else {
            show("No gap that long left on this day")
        }
    }

    /// The first gaps on `day` that fit `minutes`, for the schedule sheet.
    func openSlots(on day: CalendarDay, minutes: Int, limit: Int = 4) -> [Int] {
        let plan = engine.planDay(day)
        var busy = plan.rocks + plan.blocks.map { TimeSpan(start: Double($0.start), end: Double($0.end)) }
        busy += plan.live.map { TimeSpan(start: $0.coreStart, end: $0.leave + $0.travel) }
        busy += plan.doing.map { TimeSpan(start: $0.start, end: $0.end) }
        if let meal = plan.meal { busy.append(meal) }
        var starts: [Int] = []
        for slot in DayPlanner.freeSlots(busy, from: plan.dayStart, to: plan.bed) where slot.length >= Double(minutes) {
            starts.append(Int((slot.start / 5).rounded(.up) * 5))
            if starts.count == limit { break }
        }
        return starts
    }

    // MARK: Blocks

    /// Moves block `id` to `minute` within `blocks` and pushes the others
    /// out of its way. Done blocks, blocks already under way and events stay
    /// put, and nothing gets pushed into the past.
    func reflowed(_ blocks: [TimeBlock], moving id: String, to minute: Int, day: CalendarDay) -> [TimeBlock] {
        let setup = reflowSetup(blocks, moving: id, day: day)
        return merge(Reflow.move(id, to: minute, in: setup.movable, obstacles: setup.obstacles, earliest: setup.earliest), into: blocks)
    }

    private func reflowSetup(_ blocks: [TimeBlock], moving id: String, day: CalendarDay)
        -> (movable: [TimeBlock], obstacles: [TimeSpan], earliest: Int) {
        let plan = engine.planDay(day)
        let n = plan.isToday ? plan.now : -1
        let onDay = blocks.filter { $0.day == day }
        let fixed = onDay.filter { $0.id != id && ($0.done || Double($0.start) < n) }
        let fixedIDs = Set(fixed.map(\.id))
        let movable = onDay.filter { !fixedIDs.contains($0.id) }
        let obstacles = plan.live.map { TimeSpan(start: $0.coreStart, end: $0.coreEnd) }
            + fixed.map { TimeSpan(start: Double($0.start), end: Double($0.end)) }
        let earliest = plan.isToday ? Int(plan.dayStart) : min(Int(plan.wake), movable.map(\.start).min() ?? Int(plan.wake))
        return (movable, obstacles, earliest)
    }

    private func merge(_ changed: [TimeBlock], into blocks: [TimeBlock]) -> [TimeBlock] {
        let byID = Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) })
        return blocks.map { byID[$0.id] ?? $0 }
    }

    /// Dragging a block: everything it bumps moves live, and springs back
    /// if you drag away again.
    func dragBlock(_ id: String, by points: CGFloat, pointsPerMinute: CGFloat) {
        if blockDrag?.id != id {
            guard let block = state.block(id) else { return }
            let setup = reflowSetup(state.blocks, moving: id, day: block.day)
            blockDrag = BlockDrag(id: id, original: state.blocks, movable: setup.movable, start: block.start,
                                  obstacles: setup.obstacles, earliest: setup.earliest, target: block.start,
                                  push: engine.planDay(block.day).push)
            draggingBlockID = id
        }
        guard var drag = blockDrag else { return }
        let target = max(0, Reflow.snap(Double(drag.start) + Double(points / pointsPerMinute)))
        guard target != drag.target else { return }
        drag.target = target
        blockDrag = drag
        state.blocks = merge(Reflow.move(id, to: target, in: drag.movable, obstacles: drag.obstacles, earliest: drag.earliest),
                             into: drag.original)
    }

    func endBlockDrag() {
        guard let drag = blockDrag else { return }
        blockDrag = nil
        draggingBlockID = nil
        commit()
        if let day = state.block(drag.id)?.day {
            let push = engine.planDay(day).push
            if push > drag.push + 4 && state.settings.sound { Sounds.groan(push: push) }
        }
    }

    /// VoiceOver's swipe up and down on a block, five minutes at a time.
    func nudgeBlock(_ id: String, by minutes: Int) {
        guard let block = state.block(id) else { return }
        moveBlock(id, to: block.start + minutes)
    }

    func moveBlock(_ id: String, to minute: Int) {
        guard let block = state.block(id) else { return }
        state.blocks = reflowed(state.blocks, moving: id, to: max(0, minute), day: block.day)
        commit()
    }

    func setBlockMinutes(_ id: String, _ minutes: Int) {
        guard let block = state.block(id) else { return }
        state.updateBlock(id) { $0.minutes = max(1, minutes) }
        state.blocks = reflowed(state.blocks, moving: id, to: block.start, day: block.day)
        commit()
    }

    /// Back to the Inbox: off the day, still to do.
    func unschedule(_ id: String) {
        let title = state.block(id)?.title ?? ""
        state.blocks.removeAll { $0.id == id }
        sheet = nil
        commit()
        show("“\(title)” is back in the Inbox")
    }

    func startBlock(_ id: String) {
        guard let block = state.block(id) else { return }
        let task = block.ref.source == .app ? state.task(block.ref.id) : nil
        startSession(tasks: task.map { [$0] } ?? [], title: block.title, minutes: block.minutes)
        state.active?.blockID = block.id
        state.active?.ref = task == nil ? block.ref : nil
        commit()
    }

    /// Ticks off a block and the task behind it, wherever it lives.
    func completeBlock(_ id: String) {
        guard let block = state.block(id) else { return }
        state.updateBlock(id) { $0.done = true }
        sheet = nil
        completeSource(block.ref, minutes: block.minutes)
        commit()
        show("Done: “\(block.title)”")
    }

    /// Ticks off an Inbox task without putting it on a day.
    func completeEntry(_ key: String) {
        guard let entry = inboxEntry(key) else { return }
        sheet = nil
        completeSource(entry.task.ref, minutes: entry.estimate.minutes)
        commit()
        show("Done: “\(entry.task.title)”")
    }

    /// Marks a task done in the place it came from: Do This Now, the Inbox,
    /// Reminders or Google Tasks.
    private func completeSource(_ ref: SourceRef, minutes: Int) {
        let now = Date()
        switch ref.source {
        case .app:
            guard let task = state.task(ref.id) else { return }
            if task.kind == .recurring {
                state.log.append(LogEntry(taskID: task.id, at: now, minutes: minutes))
                state.updateTask(task.id) { $0.lastDone = now }
            } else {
                state.updateTask(task.id) { t in
                    t.done = true
                    t.doneAt = now
                    t.lastDone = now
                }
                state.finishBlocks(for: ref)
            }
        case .inbox:
            if let index = state.inboxItems.firstIndex(where: { $0.id == ref.id }) {
                state.inboxItems[index].done = true
                state.inboxItems[index].doneAt = now
            }
            state.finishBlocks(for: ref)
        case .reminders:
            RemindersSource.shared.complete(ref.id)
            reminderTasks.removeAll { $0.ref == ref }
            state.finishBlocks(for: ref)
        case .google:
            googleTasks.removeAll { $0.ref == ref }
            state.finishBlocks(for: ref)
            Task {
                do {
                    try await GoogleTasks.shared.complete(ref.id)
                } catch {
                    show("Done here, but Google Tasks didn’t hear about it. Tick it off there too.")
                }
            }
        }
    }

    func reopenBlock(_ id: String) {
        state.updateBlock(id) { $0.done = false }
        commit()
    }
}
