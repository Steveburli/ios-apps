import XCTest
@testable import DoThisNowKit

/// Meetings from a locked calendar (Alignops): nothing moves them, nothing
/// sits on them, and the rest of work hours stay open for your own tasks.
final class MeetingTests: XCTestCase {
    private func block(_ id: String, _ start: Int, _ minutes: Int, on date: CalendarDay = day(10, 14)) -> TimeBlock {
        TimeBlock(id: id, ref: SourceRef(.inbox, id), title: id, day: date, start: start, minutes: minutes)
    }

    private func meeting(_ title: String, _ start: Int, _ end: Int, on date: CalendarDay = day(10, 14)) -> Meeting {
        Meeting(id: title, title: title, day: date, start: start, end: end, calendar: "Alignops")
    }

    private func starts(_ blocks: [TimeBlock]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.start) })
    }

    /// Work 9 to 5 on weekdays, no dinner, meetings on. It's 10:00 on Wednesday the 14th.
    private func workDay(_ meetings: [Meeting]) -> PlannerState {
        var state = PlannerState()
        state.settings.dinner = .none
        state.settings.autoFill = false
        state.meetingSettings.on = true
        state.meetings = meetings
        return state
    }

    // MARK: Moving blocks

    func testABlockDroppedOnAMeetingGoesToTheNextGap() {
        let blocks = [block("x", 900, 30)]
        let standup = TimeSpan(start: 600, end: 630)
        XCTAssertEqual(starts(Reflow.move("x", to: 610, in: blocks, locked: [standup])), ["x": 630])
        // Back-to-back meetings: past both.
        let review = TimeSpan(start: 630, end: 690)
        XCTAssertEqual(starts(Reflow.move("x", to: 590, in: blocks, locked: [standup, review])), ["x": 690])
    }

    func testABlockThatFitsBeforeAMeetingStaysWhereYouPutIt() {
        let blocks = [block("x", 900, 30)]
        let standup = TimeSpan(start: 600, end: 630)
        XCTAssertEqual(starts(Reflow.move("x", to: 570, in: blocks, locked: [standup])), ["x": 570])
    }

    func testPushedBlocksHopOverMeetings() {
        let blocks = [block("a", 540, 30), block("x", 900, 30)]
        let standup = TimeSpan(start: 600, end: 630)
        // "x" lands on "a", which can't slide up past 540, so it goes down and hops the meeting.
        let moved = Reflow.move("x", to: 545, in: blocks, locked: [standup], earliest: 540)
        XCTAssertEqual(starts(moved), ["x": 545, "a": 630])
    }

    // MARK: The day

    func testMeetingsKeepTheirExactTimes() {
        let state = workDay([meeting("Standup", 615, 645)])
        let plan = engine(state).planDay(day(10, 14))
        XCTAssertEqual(plan.meetings.map(\.start), [615])
        XCTAssertEqual(plan.locked, [TimeSpan(start: 615, end: 645)])
        XCTAssertTrue(engine(state).planDay(day(10, 15)).meetings.isEmpty)
    }

    func testMeetingsAreLeftOutWhenTurnedOff() {
        var state = workDay([meeting("Standup", 615, 645)])
        state.meetingSettings.on = false
        XCTAssertTrue(engine(state).planDay(day(10, 14)).meetings.isEmpty)
    }

    func testOpenSlotsUseWorkHoursButSkipMeetings() {
        let state = workDay([meeting("Standup", 600, 630), meeting("Review", 660, 720)])
        // Work hours are open now, and only the meetings are off limits.
        XCTAssertEqual(engine(state).openSlots(on: day(10, 14), minutes: 30, limit: 3), [630, 720])
        XCTAssertEqual(engine(state).openSlots(on: day(10, 14), minutes: 45, limit: 1), [720])
    }

    func testWithoutMeetingsWorkStillBlocksOpenSlots() {
        var state = workDay([])
        state.meetingSettings.on = false
        XCTAssertEqual(engine(state).openSlots(on: day(10, 14), minutes: 30, limit: 1), [17 * 60])
    }

    func testReplanSkipsMeetings() {
        var state = workDay([meeting("Standup", 600, 660)])
        state.blocks = [block("missed", 540, 30)]
        let replan = engine(state).replan()
        XCTAssertEqual(replan.moves.map(\.to), [660])
    }

    func testAnEventOnAMeetingCantHappen() {
        var state = workDay([meeting("Client call", 1080, 1140)])
        state.events = [PlannerEvent(id: "gym", title: "Gym", day: day(10, 14), start: 1080, end: 1140, minStay: 60, travel: 0)]
        let plan = engine(state).planDay(day(10, 14))
        XCTAssertEqual(plan.ghostEvents.first?.ghost?.text, "Clashes with Client call")
    }

    func testTheNextMeetingIsTheNextThing() {
        let state = workDay([meeting("Standup", 630, 660)])
        let next = engine(state).nextBoundary()
        XCTAssertEqual(next?.label, "Standup")
        XCTAssertEqual(next?.minutes, 30)
    }

    // MARK: Calendars and saving

    func testAlignopsCalendarsAreLockedByDefault() {
        let settings = MeetingSettings()
        XCTAssertTrue(settings.locks(calendarID: "1", name: "Alignops"))
        XCTAssertTrue(settings.locks(calendarID: "2", name: "steve@alignops.com"))
        XCTAssertFalse(settings.locks(calendarID: "3", name: "Family"))
        var picked = MeetingSettings()
        picked.calendarIDs = ["3"]
        XCTAssertTrue(picked.locks(calendarID: "3", name: "Family"))
        XCTAssertFalse(picked.locks(calendarID: "1", name: "Alignops"))
    }

    func testMeetingFromACalendarEvent() {
        let start = utc.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 13, minute: 30))!
        let made = Meeting.from(eventID: "ev", title: " Sprint review ", start: start, end: start.addingTimeInterval(3600),
                                calendarName: "Alignops", calendar: utc)
        XCTAssertEqual(made.day, day(10, 14))
        XCTAssertEqual(made.start, 810)
        XCTAssertEqual(made.end, 870)
        XCTAssertEqual(made.title, "Sprint review")
        XCTAssertTrue(made.id.hasPrefix("ev@"))
    }

    func testSyncReportsChanges() {
        var state = PlannerState()
        XCTAssertTrue(state.syncMeetings([meeting("b", 700, 730), meeting("a", 600, 630)]))
        XCTAssertEqual(state.meetings.map(\.id), ["a", "b"])
        XCTAssertFalse(state.syncMeetings([meeting("a", 600, 630), meeting("b", 700, 730)]))
    }

    func testOldSavedFilesLoadWithMeetingsOff() throws {
        let state = try JSONDecoder().decode(PlannerState.self, from: Data("{}".utf8))
        XCTAssertFalse(state.meetingSettings.on)
        XCTAssertNil(state.meetingSettings.calendarIDs)
        XCTAssertTrue(state.meetings.isEmpty)
    }
}
