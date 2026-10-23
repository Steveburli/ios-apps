import XCTest
@testable import DoThisNowKit

final class EstimateTests: XCTestCase {
    func testKeysMatchTheSameThingWrittenDifferently() {
        XCTAssertEqual(Estimator.key("Mow the lawn!"), "mow lawn")
        XCTAssertEqual(Estimator.key("  mow LAWN "), "mow lawn")
        XCTAssertEqual(Estimator.key("Take a Shower"), "take shower")
        XCTAssertEqual(Estimator.key("Café run"), "cafe run")
        // A title that's all filler keeps its words.
        XCTAssertEqual(Estimator.key("The A"), "the a")
    }

    func testOutliersAreLeftOutOfTheTypicalTime() {
        // One 34-minute shower among 11–15 minute ones.
        let shower = Estimator.typical([12, 14, 11, 13, 34, 12, 15, 13])
        XCTAssertEqual(shower?.used, 7)
        XCTAssertEqual(shower?.outliers, 1)
        XCTAssertEqual(shower?.minutes ?? 0, 90.0 / 7, accuracy: 0.001)
        XCTAssertEqual(Estimator.rounded(shower?.minutes ?? 0), 13)

        let breakfast = Estimator.typical([18, 22, 15, 20, 19, 45])
        XCTAssertEqual(breakfast?.outliers, 1)
        XCTAssertEqual(breakfast?.minutes ?? 0, 18.8, accuracy: 0.001)
    }

    func testThreeRunsDropAnythingUnderHalfOrOverDoubleTheMiddle() {
        XCTAssertEqual(Estimator.typical([10, 20, 40])?.used, 3)
        let wild = Estimator.typical([5, 20, 50])
        XCTAssertEqual(wild?.used, 1)
        XCTAssertEqual(wild?.outliers, 2)
        XCTAssertEqual(wild?.minutes, 20)
    }

    func testFewRuns() {
        XCTAssertNil(Estimator.typical([]))
        XCTAssertEqual(Estimator.typical([7])?.minutes, 7)
        XCTAssertEqual(Estimator.typical([10, 20])?.minutes, 15)
    }

    func testRounding() {
        XCTAssertEqual(Estimator.rounded(0.2), 1)
        XCTAssertEqual(Estimator.rounded(12.6), 13)
        XCTAssertEqual(Estimator.rounded(33), 35)
        XCTAssertEqual(Estimator.rounded(47), 45)
    }

    func testGuessesFromWords() {
        XCTAssertEqual(Estimator.guess("Call Mom"), 15)
        XCTAssertEqual(Estimator.guess("Pay the electric bill"), 10)
        XCTAssertEqual(Estimator.guess("Cook dinner"), 45)
        XCTAssertEqual(Estimator.guess("Clean the dishes"), 15)
        XCTAssertEqual(Estimator.guess("Finish the quarterly report"), 60)
        XCTAssertEqual(Estimator.guess("Something else entirely"), 30)
    }

    func testYourTimeBeatsHistoryBeatsTheTaskBeatsAGuess() {
        var state = PlannerState()
        XCTAssertEqual(state.estimate(title: "Shower"), Estimate(minutes: 15, basis: .guess))
        XCTAssertEqual(state.estimate(title: "Shower", source: 25), Estimate(minutes: 25, basis: .source))

        for minutes in [10.0, 12, 14] {
            state.timings.append(Timing(title: "shower", start: daysAgo(minutes), seconds: minutes * 60))
        }
        XCTAssertEqual(state.estimate(title: "Shower", source: 25), Estimate(minutes: 12, basis: .history(used: 3, outliers: 0)))
        XCTAssertEqual(state.estimate(title: "Shower", custom: 20), Estimate(minutes: 20, basis: .custom))
    }

    func testOnlyRecentTimingsCount() {
        var state = PlannerState()
        for n in 0..<30 {
            // The 20 newest take 10 minutes, the 10 oldest an hour.
            let minutes: Double = n < 20 ? 10 : 60
            state.timings.append(Timing(title: "Laundry", start: daysAgo(Double(n)), seconds: minutes * 60))
        }
        XCTAssertEqual(state.estimate(title: "Laundry").minutes, 10)
    }

    func testAnActivityCountsUnderItsOtherNames() {
        var state = PlannerState()
        var commute = Activity(id: "commute", name: "Commute to work")
        commute.aliases = ["Drive to work"]
        state.activities = [commute]
        for minutes in [25.0, 30, 35] {
            state.timings.append(Timing(activityID: "commute", title: "Commute to work", start: daysAgo(minutes), seconds: minutes * 60))
        }
        XCTAssertEqual(state.activity(matching: "drive to work!")?.id, "commute")
        XCTAssertEqual(state.timings(for: "Drive to work").count, 3)
        XCTAssertEqual(state.estimate(title: "Drive to work").minutes, 30)
        XCTAssertEqual(state.estimate(title: "Something", activityID: "commute").minutes, 30)
    }

    func testTheStopwatchTimesOneThingAfterAnother() {
        var state = PlannerState()
        let start = wednesday10am
        XCTAssertNil(state.startTimer(activityID: "a", title: "Shower", at: start))
        let shower = state.startTimer(activityID: "b", title: "Get dressed", at: start.addingTimeInterval(600))
        XCTAssertEqual(shower?.title, "Shower")
        XCTAssertEqual(shower?.seconds, 600)
        XCTAssertEqual(state.running?.title, "Get dressed")

        // A mis-tap isn't saved.
        XCTAssertNil(state.stopTimer(at: start.addingTimeInterval(605)))
        XCTAssertNil(state.running)
        XCTAssertEqual(state.timings.count, 1)
    }

    func testFinishingATaskSavesHowLongItTookInAll() {
        var state = PlannerState()
        let task = makeTask("Write thank-you notes", estimate: 30) { $0.spent = 10 }
        state.tasks = [task]
        state.startSession(tasks: [task], title: task.title, minutes: 30, at: wednesday10am)
        state.endSession(finished: true, at: wednesday10am.addingTimeInterval(20 * 60))
        XCTAssertEqual(state.timings.map(\.title), ["Write thank-you notes"])
        XCTAssertEqual(state.timings.first?.seconds, 30 * 60)

        // Stopping partway doesn't count as a full run.
        state.tasks.append(makeTask("Sort photos"))
        state.startSession(tasks: [state.tasks[1]], title: "Sort photos", minutes: 30, at: wednesday10am)
        state.endSession(finished: false, at: wednesday10am.addingTimeInterval(20 * 60))
        XCTAssertEqual(state.timings.count, 1)
    }

    func testFinishingAnInboxBlockTicksEverythingOff() {
        var state = PlannerState()
        let item = InboxItem(id: "dentist", title: "Call the dentist", created: daysAgo(1))
        state.inboxItems = [item]
        let block = TimeBlock(id: "b", ref: SourceRef(.inbox, "dentist"), title: item.title, day: day(10, 14), start: 600, minutes: 10)
        state.blocks = [block]
        state.startSession(tasks: [], title: item.title, minutes: 10, at: wednesday10am)
        state.active?.blockID = "b"
        state.active?.ref = block.ref
        let message = state.endSession(finished: true, at: wednesday10am.addingTimeInterval(8 * 60))
        XCTAssertEqual(message, "Done: “Call the dentist”")
        XCTAssertTrue(state.inboxItems[0].done)
        XCTAssertTrue(state.blocks[0].done)
        XCTAssertEqual(state.timings.first?.seconds, 8 * 60)
    }
}
