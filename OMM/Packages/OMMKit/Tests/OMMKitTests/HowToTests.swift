import XCTest
@testable import OMMKit

/// The stick-figure how-to animations: coverage, timing and limb math.
final class HowToTests: XCTestCase {
    func testMidChestHasAllTenExercises() {
        let group = Catalog.group("Mid")!
        for exercise in group.allExercises {
            XCTAssertNotNil(HowTo.move(groupKey: "Mid", exercise: exercise), exercise)
        }
        XCTAssertEqual(HowTo.moves(groupKey: "Mid").count, 10)
    }

    func testEveryMoveMatchesACatalogExercise() {
        for key in HowTo.groupKeys {
            let group = Catalog.group(key)
            XCTAssertNotNil(group, key)
            for move in HowTo.moves(groupKey: key) {
                XCTAssertTrue(group?.allExercises.contains(move.exercise) ?? false, move.exercise)
            }
        }
    }

    func testGroupsWithoutDrawingsHaveNone() {
        XCTAssertNil(HowTo.move(groupKey: "Quads", exercise: "Air Squats"))
        XCTAssertNil(HowTo.move(groupKey: "Mid", exercise: "Not an exercise"))
    }

    func testMovesLoopAndHaveShortTips() {
        for key in HowTo.groupKeys {
            for move in HowTo.moves(groupKey: key) {
                XCTAssertGreaterThanOrEqual(move.frames.count, 2, move.exercise)
                XCTAssertGreaterThan(move.loopSeconds, 1, move.exercise)
                XCTAssertLessThan(move.loopSeconds, 8, move.exercise)
                XCTAssertTrue((2...3).contains(move.tips.count), move.exercise)
                XCTAssertFalse(move.tips.contains { $0.isEmpty }, move.exercise)
            }
        }
    }

    func testLimbsKeepTheirLengthThroughTheWholeLoop() {
        for key in HowTo.groupKeys {
            for move in HowTo.moves(groupKey: key) {
                var time = 0.0
                while time < move.loopSeconds {
                    let figure = move.figure(at: time)
                    for (limb, first, second) in [
                        (figure.nearArm, HowToBody.upperArm, HowToBody.forearm),
                        (figure.farArm, HowToBody.upperArm, HowToBody.forearm),
                        (figure.nearLeg, HowToBody.thigh, HowToBody.shin),
                        (figure.farLeg, HowToBody.thigh, HowToBody.shin),
                    ] {
                        XCTAssertEqual((limb.joint - limb.root).length, first, accuracy: 0.01, move.exercise)
                        XCTAssertEqual((limb.end - limb.joint).length, second, accuracy: 0.05, move.exercise)
                        XCTAssertFalse(limb.end.x.isNaN || limb.end.y.isNaN || limb.joint.x.isNaN, move.exercise)
                    }
                    XCTAssertFalse(figure.head.x.isNaN || figure.head.y.isNaN, move.exercise)
                    time += 0.05
                }
            }
        }
    }

    func testLoopWrapsAround() {
        let move = HowTo.move(groupKey: "Mid", exercise: "Standard Push-ups")!
        // Both times fall inside the first hold.
        let start = move.pose(at: 0.1)
        let wrapped = move.pose(at: move.loopSeconds * 3 + 0.1)
        XCTAssertEqual(start.shoulder, wrapped.shoulder)
        // Halfway through the first move the shoulder is between the two key poses.
        let halfway = move.pose(at: move.frames[0].hold + move.frames[0].move / 2)
        XCTAssertGreaterThan(halfway.shoulder.y, move.keyPose(0).shoulder.y)
        XCTAssertLessThan(halfway.shoulder.y, move.keyPose(1).shoulder.y)
    }

    func testReachableTargetIsReachedAndFarTargetGoesStraight() {
        let reached = HowToLimb.solve(root: HowToPoint(0, 0), target: HowToPoint(30, 0), first: 21, second: 20, bend: 1)
        XCTAssertEqual(reached.end.x, 30, accuracy: 0.001)
        XCTAssertGreaterThan(reached.joint.y, 0)
        let flipped = HowToLimb.solve(root: HowToPoint(0, 0), target: HowToPoint(30, 0), first: 21, second: 20, bend: -1)
        XCTAssertLessThan(flipped.joint.y, 0)
        let straight = HowToLimb.solve(root: HowToPoint(0, 0), target: HowToPoint(0, 100), first: 21, second: 20, bend: 1)
        XCTAssertEqual(straight.joint.y, 21, accuracy: 0.001)
        XCTAssertEqual(straight.end.y, 41, accuracy: 0.001)
    }
}
