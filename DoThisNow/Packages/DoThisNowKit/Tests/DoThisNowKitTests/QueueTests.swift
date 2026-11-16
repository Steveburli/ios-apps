import XCTest
@testable import DoThisNowKit

final class QueueTests: XCTestCase {
    private let report = SourceRef(.app, "Report")
    private let call = SourceRef(.inbox, "call")

    private func sample() -> PlannerState {
        var state = PlannerState()
        state.tasks = [makeTask("Report", tier: 1, estimate: 60)]
        state.inboxItems = [InboxItem(id: "call", title: "Call the dentist", minutes: 10, created: daysAgo(1))]
        return state
    }

    func testAQueuedTaskLeavesTheInboxAndWaitsOnItsDay() {
        var state = sample()
        XCTAssertEqual(Set(engine(state).inbox(external: []).map(\.id)), [report.key, call.key])

        state.sendToDay(report, day(10, 16), today: day(10, 14))
        XCTAssertEqual(engine(state).inbox(external: []).map(\.id), [call.key])
        XCTAssertEqual(engine(state).queued(on: day(10, 16)).map(\.task.title), ["Report"])
        XCTAssertEqual(engine(state).queued(on: day(10, 16)).first?.estimate.minutes, 60)
        XCTAssertTrue(engine(state).queued(on: day(10, 15)).isEmpty)
        XCTAssertEqual(state.queuedDay(for: report.key), day(10, 16))
    }

    func testSendingAgainMovesItAndKeepsOrder() {
        var state = sample()
        state.sendToDay(report, day(10, 16), today: day(10, 14))
        state.sendToDay(call, day(10, 16), today: day(10, 14))
        XCTAssertEqual(state.queue(on: day(10, 16)), [report, call])

        state.sendToDay(report, day(10, 17), today: day(10, 14))
        XCTAssertEqual(state.queue(on: day(10, 16)), [call])
        XCTAssertEqual(state.queue(on: day(10, 17)), [report])
    }

    func testSendingToADayTakesItOffTheTimeline() {
        var state = sample()
        state.blocks = [TimeBlock(ref: report, title: "Report", day: day(10, 15), start: 600, minutes: 60)]
        state.sendToDay(report, day(10, 16), today: day(10, 14))
        XCTAssertTrue(state.blocks.isEmpty)
        XCTAssertEqual(state.queue(on: day(10, 16)), [report])
    }

    func testRemovingFromQueuesBringsItBack() {
        var state = sample()
        state.sendToDay(call, day(10, 15), today: day(10, 14))
        state.removeFromQueues(call.key)
        XCTAssertTrue(state.queue(on: day(10, 15)).isEmpty)
        XCTAssertTrue(engine(state).inbox(external: []).contains { $0.id == call.key })
    }

    func testFinishedTasksDropOutOfTheQueue() {
        var state = sample()
        state.sendToDay(call, day(10, 15), today: day(10, 14))
        state.inboxItems[0].done = true
        XCTAssertTrue(engine(state).queued(on: day(10, 15)).isEmpty)
    }

    func testAPastQueueIsPrunedAndItsTaskComesBack() {
        var state = sample()
        state.sendToDay(report, day(10, 13), today: day(10, 13))
        XCTAssertTrue(state.queuedKeys(from: day(10, 14)).isEmpty)
        XCTAssertTrue(engine(state).inbox(external: []).contains { $0.id == report.key })
        state.prune(now: wednesday10am, calendar: utc)
        XCTAssertNil(state.queuedDay(for: report.key))
    }

    func testOldDaySettingsStillLoad() throws {
        let json = #"{"skip":["a"],"noWork":true}"#
        let config = try JSONDecoder().decode(DayConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.skip, ["a"])
        XCTAssertTrue(config.queue.isEmpty)

        var withQueue = DayConfig()
        withQueue.queue = [report]
        let round = try JSONDecoder().decode(DayConfig.self, from: JSONEncoder().encode(withQueue))
        XCTAssertEqual(round.queue, [report])
    }
}
