import XCTest
@testable import OMMKit

/// The Stretch tab: the move library, saved routines and "For you today".
final class StretchTabTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(Double(-days) * 86_400)
    }

    // MARK: Library

    func testLibraryIDsAreUniqueAndEveryMoveHasAPicture() {
        let ids = Stretches.library.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertNotNil(StretchFigures.figure(for: id), id)
        }
        XCTAssertEqual(StretchFigures.all.count, ids.count)
    }

    func testFiguresStayInTheirBox() {
        for (id, figure) in StretchFigures.all {
            for line in figure.body + figure.props {
                XCTAssertEqual(line.count % 2, 0, id)
                XCTAssertGreaterThanOrEqual(line.count, 4, id)
                XCTAssertTrue(line.allSatisfy { (0...100).contains($0) }, id)
            }
        }
    }

    func testEveryAreaAndGroupHasMoves() {
        for area in Catalog.areas {
            XCTAssertFalse(Stretches.moves(in: area).isEmpty, area)
        }
        for group in Catalog.groups {
            XCTAssertFalse(Stretches.moves(for: group.key).isEmpty, group.key)
        }
        let known = Set(Catalog.groups.map(\.key))
        for stretch in Stretches.library {
            XCTAssertTrue(Catalog.areas.contains(stretch.area), stretch.id)
            XCTAssertTrue(stretch.groups.allSatisfy(known.contains), stretch.id)
        }
    }

    func testLibraryIncludesYoga() {
        XCTAssertGreaterThanOrEqual(Stretches.library.filter { $0.kind == .yoga }.count, 10)
    }

    // MARK: Saved routines

    func testRoutineUsesItsOwnHoldTimes() {
        let routine = StretchRoutine(name: "Morning", items: [
            .init(stretchID: "cobra-lift", holdSeconds: 45),
            .init(stretchID: "quad-pull", holdSeconds: 20),
        ])
        XCTAssertEqual(routine.steps.map(\.holdSeconds), [45, 20, 20])
        XCTAssertEqual(Stretches.seconds(for: routine.steps), 85)
        XCTAssertEqual(Stretches.minutes(for: routine.steps), 2)
        XCTAssertTrue(routine.isReady)
    }

    func testRoutineNeedsANameAndAMove() {
        XCTAssertFalse(StretchRoutine(name: "  ", items: [.init(stretchID: "cobra-lift")]).isReady)
        XCTAssertFalse(StretchRoutine(name: "Empty").isReady)
        XCTAssertFalse(StretchRoutine(name: "Gone", items: [.init(stretchID: "no-such-move")]).isReady)
    }

    func testRoutineRoundTripsThroughJSON() throws {
        let routine = StretchRoutine(name: "Evening", items: [.init(stretchID: "childs-pose", holdSeconds: 60)])
        let data = try JSONEncoder().encode([routine])
        XCTAssertEqual(try JSONDecoder().decode([StretchRoutine].self, from: data), [routine])
    }

    // MARK: For you today

    func testSoreGroupsAreTodayAndYesterdayOnly() {
        var program = ProgramState()
        program.lastTrained = ["Biceps": daysAgo(0), "Hams": daysAgo(1), "Lats": daysAgo(2)]
        let sore = StretchPlanner.soreGroups(in: program, now: now, calendar: utc)
        XCTAssertEqual(sore.map(\.key), ["Biceps", "Hams"])
    }

    func testUpcomingPrefersPickedGroups() {
        let program = ProgramState()
        let upcoming = StretchPlanner.upcomingGroups(in: program, picked: ["Front", "Quads"])
        XCTAssertEqual(upcoming.map(\.key), ["Front", "Quads"])
    }

    func testUpcomingTakesTheLongestRestedUnfinishedGroupPerSection() {
        var program = ProgramState()
        // Every upper group trained recently except Rotator; Mid is finished.
        for group in Catalog.groups where group.category == .upper {
            program.lastTrained[group.key] = daysAgo(1)
        }
        program.lastTrained["Rotator"] = daysAgo(6)
        program.progress["Mid"] = 3
        let upcoming = StretchPlanner.upcomingGroups(in: program, picked: [])
        XCTAssertEqual(upcoming.count, 3)
        XCTAssertEqual(upcoming[0].key, "Rotator")
        XCTAssertEqual(upcoming.map(\.category), [.upper, .lower, .core])
    }

    func testUpcomingSkipsExcludedGroups() {
        let program = ProgramState()
        let first = StretchPlanner.upcomingGroups(in: program, picked: [])
        let next = StretchPlanner.upcomingGroups(in: program, picked: [], excluding: first)
        XCTAssertTrue(Set(first.map(\.key)).isDisjoint(with: next.map(\.key)))
    }

    func testPlannedRoutineFitsTheLengthAndCoversEveryGroup() {
        let groups = ["Hams", "Biceps", "Oblique"].compactMap(Catalog.group)
        let steps = StretchPlanner.routine(for: groups, minutes: 5)
        XCTAssertLessThanOrEqual(Stretches.seconds(for: steps), 300)
        for group in groups {
            XCTAssertTrue(steps.contains { $0.stretch.groups.contains(group.key) }, group.key)
        }
        // Standing moves come before floor moves.
        let postures = steps.map(\.stretch.posture)
        XCTAssertEqual(postures, postures.sorted())
    }

    func testLongerRoutineHasMoreMoves() {
        let groups = ["Quads", "Lats"].compactMap(Catalog.group)
        let short = StretchPlanner.routine(for: groups, minutes: 5)
        let long = StretchPlanner.routine(for: groups, minutes: 15)
        XCTAssertGreaterThan(long.count, short.count)
        XCTAssertTrue(StretchPlanner.routine(for: [], minutes: 10).isEmpty)
    }

    func testOldStepsKeepTheirDefaultHold() {
        let step = StretchStep(stretch: Stretches.library[0], side: nil)
        XCTAssertEqual(step.holdSeconds, Stretches.holdSeconds)
    }
}
