import XCTest
@testable import DoThisNowKit

final class BlockTests: XCTestCase {
    private func block(_ id: String, _ start: Int, _ minutes: Int, on date: CalendarDay = day(10, 15)) -> TimeBlock {
        TimeBlock(id: id, ref: SourceRef(.inbox, id), title: id, day: date, start: start, minutes: minutes)
    }

    private func starts(_ blocks: [TimeBlock]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.start) })
    }

    // MARK: Moving blocks

    func testLandingOnABlockPushesItAndCarriesOn() {
        let blocks = [block("a", 600, 30), block("b", 640, 30), block("c", 670, 30), block("d", 800, 30), block("x", 900, 60)]
        let moved = Reflow.move("x", to: 620, in: blocks)
        // "a" sat mostly above the new spot, so it slides up; "b" and "c" slide down; "d" isn't in the way.
        XCTAssertEqual(starts(moved), ["a": 590, "x": 620, "b": 680, "c": 710, "d": 800])
    }

    func testBlocksThatArentInTheWayStayPut() {
        let blocks = [block("a", 600, 30), block("b", 700, 30), block("x", 900, 30)]
        XCTAssertEqual(starts(Reflow.move("x", to: 640, in: blocks)), ["a": 600, "b": 700, "x": 640])
    }

    func testABlockWithNoRoomAboveGoesBelow() {
        let blocks = [block("a", 600, 30), block("x", 900, 30)]
        let moved = Reflow.move("x", to: 605, in: blocks, earliest: 590)
        XCTAssertEqual(starts(moved), ["a": 635, "x": 605])
    }

    func testPushedBlocksHopOverEvents() {
        let blocks = [block("c", 690, 30), block("x", 900, 30)]
        let event = TimeSpan(start: 700, end: 760)
        XCTAssertEqual(starts(Reflow.move("x", to: 670, in: blocks, obstacles: [event])), ["c": 760, "x": 670])
        // Upward too.
        let up = [block("a", 760, 30), block("x", 900, 30)]
        XCTAssertEqual(starts(Reflow.move("x", to: 770, in: up, obstacles: [event])), ["a": 670, "x": 770])
    }

    func testNoTwoBlocksEverOverlap() {
        var blocks = (0..<6).map { block("b\($0)", 540 + $0 * 45, 30 + ($0 % 3) * 10) }
        for (id, target) in [("b3", 550), ("b0", 700), ("b5", 560), ("b2", 545), ("b4", 820)] {
            blocks = Reflow.move(id, to: target, in: blocks, obstacles: [TimeSpan(start: 750, end: 780)], earliest: 480)
            let sorted = blocks.sorted { $0.start < $1.start }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                XCTAssertLessThanOrEqual(a.end, b.start, "\(a.id) overlaps \(b.id) after moving \(id)")
            }
        }
    }

    func testSnap() {
        XCTAssertEqual(Reflow.snap(612.4), 610)
        XCTAssertEqual(Reflow.snap(613), 615)
    }

    // MARK: On the Day

    func testOtherThingsFlowAroundYourBlocks() {
        var state = PlannerState()
        state.blocks = [block("errand", 1080, 60)]
        let plan = engine(state).planDay(day(10, 15))
        XCTAssertEqual(plan.blocks.map(\.id), ["errand"])
        // Dinner would start at 6:30, but the block holds 6:00–7:00.
        XCTAssertEqual(plan.meal, TimeSpan(start: 1140, end: 1175))
    }

    func testATaskOnTheDayIsntPlacedTwice() {
        var state = PlannerState()
        let report = makeTask("Report", tier: 1, estimate: 60)
        state.tasks = [report]
        XCTAssertEqual(engine(state).planDay(day(10, 15)).items.map(\.chunk.id), ["Report"])

        state.blocks = [TimeBlock(ref: SourceRef(.app, "Report"), title: "Report", day: day(10, 15), start: 1200, minutes: 60)]
        XCTAssertTrue(engine(state).planDay(day(10, 15)).items.isEmpty)
    }

    func testAutoFillOffLeavesOnlyYourBlocks() {
        var state = PlannerState()
        state.tasks = [makeTask("Report", tier: 1, estimate: 60)]
        state.settings.autoFill = false
        XCTAssertTrue(engine(state).planDay(day(10, 15)).items.isEmpty)
    }

    func testABlockPastBedtimePushesSleep() {
        var state = PlannerState()
        state.settings.dinner = .none
        state.blocks = [block("late", 1370, 60)]
        let plan = engine(state).planDay(day(10, 15))
        XCTAssertEqual(plan.sleepStart, 1430)
        XCTAssertEqual(plan.push, 50)
    }

    // MARK: The Inbox

    private func source(_ id: String, _ source: TaskSource = .reminders, list: String = "home", due: Date? = nil,
                        priority: Int = 0, notes: String = "") -> SourceTask {
        SourceTask(ref: SourceRef(source, id), title: id, notes: notes, listID: list, listName: list, due: due, priority: priority)
    }

    func testFilters() {
        var filter = SourceFilter(on: true)
        let today = day(10, 14)
        let undated = source("undated")
        let tomorrow = source("tomorrow", due: day(10, 15).startDate(calendar: utc))
        let nextWeek = source("next week", due: day(10, 21).startDate(calendar: utc))
        let overdue = source("overdue", due: day(10, 10).startDate(calendar: utc))
        func allowed() -> [String] {
            [undated, tomorrow, nextWeek, overdue].filter { filter.allows($0, today: today, calendar: utc) }.map(\.ref.id)
        }
        XCTAssertEqual(allowed(), ["undated", "tomorrow", "next week", "overdue"])
        filter.due = .threeDays
        XCTAssertEqual(allowed(), ["undated", "tomorrow", "overdue"])
        filter.undated = false
        filter.due = .today
        XCTAssertEqual(allowed(), ["overdue"])

        var keyword = SourceFilter(on: true)
        keyword.keyword = "plan"
        XCTAssertTrue(keyword.allows(source("x", notes: "#plan this"), today: today, calendar: utc))
        XCTAssertFalse(keyword.allows(source("y"), today: today, calendar: utc))

        var lists = SourceFilter(on: true, hiddenLists: ["groceries"])
        lists.minPriority = 2
        XCTAssertFalse(lists.allows(source("milk", list: "groceries", priority: 3), today: today, calendar: utc))
        XCTAssertFalse(lists.allows(source("low", priority: 1), today: today, calendar: utc))
        XCTAssertTrue(lists.allows(source("high", priority: 3), today: today, calendar: utc))
    }

    func testTheInboxGathersEverySourceThatsOn() {
        var state = PlannerState()
        state.tasks = [
            makeTask("Top", tier: 1, estimate: 45),
            makeTask("Someday", tier: 4),
            makeTask("Snoozed", tier: 2) { $0.snoozeUntil = wednesday10am.addingTimeInterval(3600) },
            makeTask("Planned", tier: 2),
            makeTask("Hidden", tier: 2),
        ]
        state.inboxItems = [InboxItem(id: "typed", title: "Typed in", minutes: 10, created: daysAgo(1))]
        state.blocks = [TimeBlock(ref: SourceRef(.app, "Planned"), title: "Planned", day: day(10, 15), start: 600, minutes: 30)]
        state.inbox.hidden = ["app:Hidden"]
        let reminder = source("Dentist", due: day(10, 14).startDate(calendar: utc))

        var titles = engine(state).inbox(external: [reminder]).map(\.task.title)
        // Reminders are off until you turn them on.
        XCTAssertEqual(titles, ["Top", "Typed in"])

        state.inbox.reminders.on = true
        titles = engine(state).inbox(external: [reminder]).map(\.task.title)
        // Due soonest first.
        XCTAssertEqual(titles, ["Dentist", "Top", "Typed in"])

        let entries = engine(state).inbox(external: [])
        XCTAssertEqual(entries.first { $0.task.title == "Top" }?.estimate, Estimate(minutes: 45, basis: .source))
        state.inbox.minutes["app:Top"] = 25
        XCTAssertEqual(engine(state).inbox(external: []).first?.estimate.minutes, 25)
    }

    // MARK: Reminders

    private func reminder(_ id: String, priority: Int = 0, due: CalendarDay? = nil, list: String = "work") -> SourceTask {
        SourceTask(ref: SourceRef(.reminders, id), title: id, notes: "note", listID: list, listName: list,
                   due: due?.startDate(calendar: utc), priority: priority)
    }

    private func syncing(_ open: [SourceTask], _ state: inout PlannerState) {
        state.syncReminders(open, now: wednesday10am, calendar: utc)
    }

    func testRemindersBecomeTasksThatNowCanPick() {
        var state = PlannerState()
        state.inbox.reminders.on = true
        syncing([reminder("High", priority: 3, due: day(10, 16)), reminder("Medium", priority: 2), reminder("Low", priority: 1), reminder("None")], &state)

        XCTAssertEqual(state.tasks.map(\.tier), [1, 2, 3, 3])
        let first = state.tasks[0]
        XCTAssertEqual(first.reminderID, "High")
        XCTAssertEqual(first.notes, "note")
        XCTAssertEqual(first.deadline, day(10, 16))
        XCTAssertEqual(first.places, [.anywhere])

        var context = NowContext()
        context.place = .office
        let picks = engine(state).recommend(context, available: 60, skip: [])
        XCTAssertTrue(picks.contains { $0.tasks.contains { $0.id == first.id } }, "A reminder can be picked wherever you are")
    }

    func testSyncingAgainKeepsYourChangesAndTakesTheirs() {
        var state = PlannerState()
        state.inbox.reminders.on = true
        syncing([reminder("Call")], &state)
        state.updateTask(state.tasks[0].id) { $0.tier = 1 }

        var changed = reminder("Call", priority: 1, due: day(10, 20))
        changed.title = "Call the bank"
        syncing([changed], &state)

        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertEqual(state.tasks[0].title, "Call the bank")
        XCTAssertEqual(state.tasks[0].deadline, day(10, 20))
        XCTAssertEqual(state.tasks[0].tier, 1, "Your priority level stays")
    }

    func testTasksFromALabeledListCarryTheLabel() {
        var state = PlannerState()
        state.inbox.reminders.on = true
        state.inbox.listLabels = ["house": "From my wife", "blank": "  "]
        syncing([reminder("Porch light", list: "house"), reminder("Call"), reminder("Gutter", list: "blank")], &state)
        XCTAssertEqual(state.tasks.map { state.listLabel(for: $0) }, ["From my wife", nil, nil])
        XCTAssertEqual(state.listLabel(for: SourceRef(.app, state.tasks[0].id)), "From my wife")
        XCTAssertNil(state.listLabel(for: SourceRef(.inbox, state.tasks[0].id)))
    }

    func testRemindersStayOutWhileTurnedOffOrFilteredOut() {
        var state = PlannerState()
        syncing([reminder("Off")], &state)
        XCTAssertTrue(state.tasks.isEmpty)

        state.inbox.reminders.on = true
        state.inbox.reminders.hiddenLists = ["groceries"]
        syncing([reminder("Milk", list: "groceries"), reminder("Call")], &state)
        XCTAssertEqual(state.tasks.map(\.title), ["Call"])

        state.inbox.reminders.hiddenLists = ["work"]
        syncing([reminder("Milk", list: "groceries"), reminder("Call")], &state)
        XCTAssertEqual(state.tasks.map(\.title), ["Milk"], "A list you turn off leaves, and one you turn on arrives")
    }

    func testTickingOffInRemindersFinishesTheTask() {
        var state = PlannerState()
        state.inbox.reminders.on = true
        syncing([reminder("Call")], &state)
        let id = state.tasks[0].id
        state.blocks = [TimeBlock(ref: SourceRef(.app, id), title: "Call", day: day(10, 14), start: 600, minutes: 30)]

        syncing([], &state)
        XCTAssertTrue(state.tasks[0].done)
        XCTAssertTrue(state.blocks[0].done)
        XCTAssertTrue(state.remindersToClose.isEmpty, "Nothing to send back")

        syncing([reminder("Call")], &state)
        XCTAssertFalse(state.tasks[0].done, "A repeating reminder's next round comes back")
        XCTAssertTrue(state.remindersToReopen.isEmpty)
    }

    func testFinishingHereClosesAndRestoringReopens() {
        var state = PlannerState()
        state.inbox.reminders.on = true
        syncing([reminder("Call")], &state)
        let id = state.tasks[0].id

        state.updateTask(id) { $0.done = true }
        XCTAssertEqual(state.remindersToClose.map(\.id), [id])
        state.updateTask(id) { $0.reminderClosed = true }
        XCTAssertTrue(state.remindersToClose.isEmpty)

        state.restore(id, now: wednesday10am)
        XCTAssertEqual(state.remindersToReopen.map(\.id), [id])
    }

    func testLettingGoAndDeletingLeaveTheReminderAlone() {
        var state = PlannerState()
        state.inbox.reminders.on = true
        syncing([reminder("Keep"), reminder("Drop")], &state)
        let keep = state.tasks[0].id, drop = state.tasks[1].id

        state.letGo(keep, now: wednesday10am)
        state.deleteTask(drop)
        XCTAssertTrue(state.remindersToClose.isEmpty)

        syncing([reminder("Keep"), reminder("Drop")], &state)
        XCTAssertEqual(state.tasks.map(\.id), [keep], "A deleted one doesn't come back")
        XCTAssertTrue(state.tasks[0].archived, "A let-go one stays let go")
    }

    func testTheTaskYoureTimingStaysWhenFiltersChange() {
        var state = PlannerState()
        state.inbox.reminders.on = true
        syncing([reminder("Call")], &state)
        let task = state.tasks[0]
        state.startSession(tasks: [task], title: task.title, minutes: 30, at: wednesday10am)

        state.inbox.reminders.on = false
        syncing([reminder("Call")], &state)
        XCTAssertEqual(state.tasks.count, 1)
    }

    // MARK: Saving

    func testNewFieldsSaveAndOldFilesStillLoad() throws {
        var state = PlannerState()
        state.loadExamples(now: wednesday10am, calendar: utc)
        state.wake.alarm.codes = [WakeCode(name: "Toothpaste", payload: "0123456789")]
        state.running = RunningTimer(activityID: nil, title: "Shower", startedAt: wednesday10am)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(PlannerState.self, from: data), state)

        let old = Data(#"{"tasks":[],"settings":{"wake":420}}"#.utf8)
        let loaded = try JSONDecoder().decode(PlannerState.self, from: old)
        XCTAssertTrue(loaded.blocks.isEmpty)
        XCTAssertTrue(loaded.settings.autoFill)
        XCTAssertEqual(loaded.wake, WakeSettings())
        XCTAssertEqual(loaded.inbox, InboxSettings())
    }

    func testRemovingExamplesClearsTheNewThingsToo() {
        var state = PlannerState()
        state.loadExamples(now: wednesday10am, calendar: utc)
        XCTAssertFalse(state.blocks.isEmpty)
        XCTAssertFalse(state.timings.isEmpty)
        state.removeExamples()
        XCTAssertTrue(state.blocks.isEmpty)
        XCTAssertTrue(state.timings.isEmpty)
        XCTAssertTrue(state.activities.isEmpty)
        XCTAssertTrue(state.inboxItems.isEmpty)
    }
}
