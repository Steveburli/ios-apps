import XCTest
@testable import DoThisNowKit

final class EngineTests: XCTestCase {
    private func homeContext(minutes: Int? = 60) -> NowContext {
        var context = NowContext()
        context.timeMinutes = minutes
        context.place = .home
        return context
    }

    func testRemaining() {
        var state = PlannerState()
        let guitar = makeTask("Guitar", .recurring) { $0.weekly = 120 }
        let report = makeTask("Report", estimate: 30) { $0.spent = 28 }
        state.tasks = [guitar, report]
        state.log = [
            LogEntry(taskID: "Guitar", at: daysAgo(1), minutes: 30),   // this week
            LogEntry(taskID: "Guitar", at: daysAgo(4), minutes: 45),   // last week (Saturday)
        ]
        let e = engine(state)
        XCTAssertEqual(e.weekMinutes("Guitar"), 30)
        XCTAssertEqual(e.remaining(guitar), 90)
        XCTAssertEqual(e.remaining(report), 5)
    }

    func testFits() {
        let e = engine(PlannerState())
        let deep = makeTask("Deep", places: [.computer]) { $0.focus = .deep }
        let phoneOnly = makeTask("Phone", places: [.phone])
        let anywhere = makeTask("Anywhere", places: [.anywhere])

        var context = NowContext()
        context.place = .computer
        XCTAssertTrue(e.fits(deep, context))
        context.multitasking = true
        XCTAssertFalse(e.fits(deep, context))

        context = NowContext()
        context.place = .phone
        context.tv = true
        XCTAssertTrue(e.fits(phoneOnly, context))
        XCTAssertFalse(e.fits(anywhere, context))
        XCTAssertFalse(e.fits(deep, context))
    }

    func testSessionMinutes() {
        let e = engine(PlannerState())
        let long = makeTask("Long", estimate: 60)
        XCTAssertEqual(e.sessionMinutes(long, available: 30), 30)
        XCTAssertEqual(e.sessionMinutes(long, available: 120), 45)
        XCTAssertEqual(e.sessionMinutes(long, available: 5), 0)

        let binge = makeTask("Binge", estimate: 90) { $0.binge = true }
        XCTAssertEqual(e.sessionMinutes(binge, available: 120), 90)

        let goal = makeTask("Goal", .recurring) { $0.weekly = 120; $0.minBlock = 20 }
        XCTAssertEqual(e.sessionMinutes(goal, available: 15), 0)
        XCTAssertEqual(e.sessionMinutes(goal, available: 25), 25)
    }

    func testHigherTierWins() {
        var state = PlannerState()
        state.tasks = [makeTask("Medium", tier: 3), makeTask("Top", tier: 1)]
        let picks = engine(state).recommend(homeContext(), available: 60)
        XCTAssertEqual(picks.map(\.title), ["Top", "Medium"])
        XCTAssertTrue(picks[0].reasons.contains("It’s at the top of your list"))
        XCTAssertTrue(picks[0].finish)
    }

    func testSnoozedAndSkippedTasksAreLeftOut() {
        var state = PlannerState()
        state.tasks = [
            makeTask("Snoozed") { $0.snoozeUntil = wednesday10am.addingTimeInterval(3600) },
            makeTask("Skipped"),
            makeTask("Done") { $0.done = true },
            makeTask("Open"),
        ]
        let picks = engine(state).recommend(homeContext(), available: 60, skip: ["Skipped"])
        XCTAssertEqual(picks.map(\.title), ["Open"])
    }

    func testErrandsBundleIntoOneTrip() {
        var state = PlannerState()
        state.tasks = [
            makeTask("Dry cleaning", .errand, places: [.errand], estimate: 10),
            makeTask("Library", .errand, places: [.errand], estimate: 10),
        ]
        let picks = engine(state).recommend(homeContext(), available: 60)
        XCTAssertEqual(picks.count, 1)
        XCTAssertEqual(picks[0].kind, .errands)
        XCTAssertEqual(picks[0].title, "Errand run: 2 stops")
        XCTAssertEqual(picks[0].minutes, 50) // 10 + (10 + 10) × 2
        XCTAssertEqual(picks[0].reasons.first, "2 stops in one trip instead of 2 trips")

        // One errand alone only comes up when you're already out.
        state.tasks.removeLast()
        XCTAssertTrue(engine(state).recommend(homeContext(), available: 60).isEmpty)
        var out = homeContext()
        out.place = .errand
        let single = engine(state).recommend(out, available: 60)
        XCTAssertEqual(single.first?.minutes, 30)
        XCTAssertEqual(single.first?.reasons.first, "You’re already out")
    }

    func testLittleThingsBecomeASweep() {
        var state = PlannerState()
        state.tasks = [
            makeTask("Water plants", estimate: 10),
            makeTask("Fold laundry", estimate: 10),
            makeTask("Wipe counters", estimate: 10),
        ]
        let picks = engine(state).recommend(homeContext(), available: 60)
        XCTAssertEqual(picks.first?.kind, .sweep)
        XCTAssertEqual(picks.first?.title, "3 little things around the house")
        XCTAssertEqual(picks.first?.minutes, 30)
        XCTAssertEqual(picks.count, 4)
    }

    func testDeadlineReason() {
        var state = PlannerState()
        state.tasks = [makeTask("Taxes") { $0.deadline = day(10, 15); $0.stakes = 8 }]
        let pick = engine(state).recommend(homeContext(), available: 60).first
        XCTAssertEqual(pick?.reasons.first, "Due tomorrow, and you said you’d be mad if it slipped")
    }

    func testNextBoundaryDuringWork() {
        let e = engine(PlannerState())
        let next = e.nextBoundary()
        XCTAssertEqual(next?.label, "work ends")
        XCTAssertEqual(next?.at, 1020)
        XCTAssertEqual(next?.minutes, 420)
        XCTAssertEqual(e.availableMinutes(NowContext()), 420)
        var fixed = NowContext()
        fixed.timeMinutes = 15
        XCTAssertEqual(e.availableMinutes(fixed), 15)
    }

    func testNudges() {
        var state = PlannerState()
        state.tasks = [
            makeTask("Stale", created: daysAgo(50)),
            makeTask("Goal", .recurring, created: daysAgo(20)) { $0.weekly = 120 },
            makeTask("New", created: daysAgo(2)),
        ]
        let nudges = engine(state).nudges()
        XCTAssertEqual(nudges.count, 2)
        let loosen = nudges.first { $0.kind == .loosen }
        XCTAssertEqual(loosen?.suggest, 60)  // 40% of 120 is 48, rounded up to 60
        let serious = nudges.first { $0.kind == .serious }
        XCTAssertEqual(serious?.text, "“Stale” has been on your list for 7 weeks and you haven’t started.")
        // Loosen weighs 2 − 0 / 120 = 2; serious weighs 50 / 45.
        XCTAssertEqual(nudges.first?.kind, .loosen)
    }

    func testEndingSessions() {
        var state = PlannerState()
        state.tasks = [makeTask("Report", estimate: 60)]
        state.startSession(tasks: state.tasks, title: "Report", minutes: 30, at: wednesday10am)
        let message = state.endSession(finished: false, at: wednesday10am.addingTimeInterval(25 * 60))
        XCTAssertEqual(message, "Logged 25m on “Report”")
        XCTAssertEqual(state.task("Report")?.spent, 25)
        XCTAssertNil(state.active)
        XCTAssertEqual(state.log.count, 1)

        state.startSession(tasks: state.tasks, title: "Report", minutes: 35, at: wednesday10am)
        state.pauseSession(at: wednesday10am.addingTimeInterval(10 * 60))
        state.resumeSession(at: wednesday10am.addingTimeInterval(20 * 60))
        XCTAssertEqual(state.active?.elapsed(at: wednesday10am.addingTimeInterval(30 * 60)), 20 * 60)
        XCTAssertEqual(state.endSession(finished: true, at: wednesday10am.addingTimeInterval(30 * 60)), "Done: “Report”")
        XCTAssertEqual(state.task("Report")?.done, true)
    }

    func testBundleSessions() {
        var state = PlannerState()
        state.tasks = [makeTask("A", estimate: 10), makeTask("B", estimate: 10), makeTask("C", estimate: 10)]
        state.startSession(tasks: state.tasks, title: "3 little things", minutes: 30, at: wednesday10am)
        XCTAssertEqual(state.active?.bundle, true)
        state.tick(taskID: "A", checked: true, at: wednesday10am)
        XCTAssertEqual(state.endSession(finished: true, at: wednesday10am), "Nice. 3 crossed off.")
        XCTAssertTrue(state.tasks.allSatisfy(\.done))
    }

    func testAlreadyDoneAndSnooze() {
        var state = PlannerState()
        state.tasks = [makeTask("Report")]
        let candidate = engine(state).recommend(homeContext(), available: 60)[0]
        state.markAlreadyDone(candidate, when: .lastWeek, now: wednesday10am)
        XCTAssertEqual(state.task("Report")?.doneAt, daysAgo(7))

        let tomorrow = SnoozeChoice.tomorrowMorning.date(from: wednesday10am, wake: 420, calendar: utc)
        XCTAssertEqual(utc.dateComponents([.day, .hour], from: tomorrow), DateComponents(day: 15, hour: 7))
    }

    func testReorder() {
        var state = PlannerState()
        state.tasks = [makeTask("A", tier: 1), makeTask("B", tier: 2), makeTask("C", tier: 3) { $0.done = true }]
        state.applyOrder([(id: "B", tier: 1), (id: "A", tier: 4)])
        XCTAssertEqual(state.tasks.map(\.id), ["B", "A", "C"])
        XCTAssertEqual(state.tasks.map(\.tier), [1, 4, 3])
    }
}
