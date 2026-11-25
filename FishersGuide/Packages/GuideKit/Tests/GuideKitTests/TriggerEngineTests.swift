import XCTest
@testable import GuideKit

final class TriggerEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let center = GeoPoint(lat: 40.0, lon: -86.0)

    func poi(_ id: String = "a", radius: Double = 200, approach: [HeadingRange] = [], priority: Int = 0,
             teaser: String? = "a place", at point: GeoPoint? = nil) -> Stop {
        Stop(id: id, title: "Stop \(id)", subtitle: "", category: .history, location: point ?? center,
             radius: radius, approach: approach, narration: "Story \(id).", teaser: teaser, priority: priority)
    }

    /// A fix `meters` from the center along `bearingFromCenter`, traveling `course`.
    func fix(_ meters: Double, from bearingFromCenter: Double, course: Double?, speed: Double = 20, after: TimeInterval = 0) -> Fix {
        Fix(point: Geo.destination(from: center, bearing: bearingFromCenter, meters: meters),
            course: course, speed: speed, time: t0.addingTimeInterval(after))
    }

    func testTriggersEarlyWhenDrivingTowardIt() {
        var engine = TriggerEngine()
        // 500 m south, driving north at 20 m/s: radius 200 + lead 400 = 600 m reach.
        let trigger = engine.next(stops: [poi()], fix: fix(500, from: 180, course: 0))
        XCTAssertEqual(trigger?.kind, .arrival)
        XCTAssertEqual(trigger?.side, .ahead)
    }

    func testNoLeadWhenDrivingAway() {
        let engine = TriggerEngine()
        // 500 m south, driving south (away): no lead, out of radius, and it's behind.
        XCTAssertTrue(engine.candidates(stops: [poi()], fix: fix(500, from: 180, course: 180)).isEmpty)
    }

    func testPassedStopDoesNotPlayLate() {
        let engine = TriggerEngine()
        // 150 m north of it (inside the 200 m circle) but driving north, away: too late.
        XCTAssertTrue(engine.candidates(stops: [poi()], fix: fix(150, from: 0, course: 0)).isEmpty)
        // Right next to it while leaving still plays.
        XCTAssertFalse(engine.candidates(stops: [poi()], fix: fix(50, from: 0, course: 0)).isEmpty)
    }

    func testSideOfRoad() {
        let engine = TriggerEngine()
        // Driving north, stop is 150 m east of the road and 300 m ahead → on the right.
        let start = Geo.destination(from: Geo.destination(from: center, bearing: 270, meters: 150), bearing: 180, meters: 300)
        let f = Fix(point: start, course: 0, speed: 20, time: t0)
        XCTAssertEqual(engine.candidates(stops: [poi()], fix: f).first?.side, .right)
        // Driving south past the same spot from the other side → on the left.
        let back = Geo.destination(from: Geo.destination(from: center, bearing: 270, meters: 150), bearing: 0, meters: 300)
        let g = Fix(point: back, course: 180, speed: 20, time: t0)
        XCTAssertEqual(engine.candidates(stops: [poi()], fix: g).first?.side, .left)
    }

    func testOnlyOncePerCooldown() {
        var engine = TriggerEngine()
        XCTAssertNotNil(engine.next(stops: [poi()], fix: fix(100, from: 180, course: 0)))
        XCTAssertNil(engine.next(stops: [poi()], fix: fix(80, from: 180, course: 0, after: 10)))
        // Seven hours later it can play again.
        XCTAssertNotNil(engine.next(stops: [poi()], fix: fix(80, from: 180, course: 0, after: 7 * 3600)))
    }

    func testApproachHeadingsFilterDirection() {
        let northOnly = poi(approach: [HeadingRange(from: 300, to: 60)])
        let engine = TriggerEngine()
        XCTAssertFalse(engine.candidates(stops: [northOnly], fix: fix(300, from: 180, course: 0)).isEmpty)
        XCTAssertTrue(engine.candidates(stops: [northOnly], fix: fix(300, from: 0, course: 180)).isEmpty)
        // Parked inside the circle with no course: still plays.
        XCTAssertFalse(engine.candidates(stops: [northOnly], fix: fix(100, from: 0, course: nil, speed: 0)).isEmpty)
    }

    func testDirectionalNarration() {
        var stop = poi()
        stop.directional = [DirectionalNarration(heading: HeadingRange(from: 300, to: 60), text: "Northbound story.")]
        let engine = TriggerEngine()
        let north = engine.candidates(stops: [stop], fix: fix(300, from: 180, course: 0)).first
        XCTAssertTrue(north?.script.hasSuffix("Northbound story.") ?? false)
        let south = engine.candidates(stops: [stop], fix: fix(300, from: 0, course: 180)).first
        XCTAssertTrue(south?.script.hasSuffix("Story a.") ?? false)
    }

    func testSlowSpeedIgnoresNoisyCourse() {
        let engine = TriggerEngine()
        // Walking pace, 400 m away: no lead, so nothing yet.
        XCTAssertTrue(engine.candidates(stops: [poi()], fix: fix(400, from: 180, course: 0, speed: 1)).isEmpty)
        XCTAssertFalse(engine.candidates(stops: [poi()], fix: fix(150, from: 180, course: 0, speed: 1)).isEmpty)
    }

    func testPriorityThenCloseness() {
        let near = poi("near", priority: 0)
        let important = poi("important", priority: 5, at: Geo.destination(from: center, bearing: 0, meters: 150))
        let engine = TriggerEngine()
        let list = engine.candidates(stops: [near, important], fix: fix(50, from: 180, course: 0))
        XCTAssertEqual(list.map(\.stop.id), ["important", "near"])
    }

    func testAreasYieldToPOIs() {
        let area = Stop(id: "town", title: "Town", subtitle: "", category: .area, kind: .area,
                        location: center, radius: 5000, narration: "Welcome.", priority: 10)
        var engine = TriggerEngine()
        let f = fix(100, from: 180, course: 0)
        XCTAssertEqual(engine.next(stops: [area, poi()], fix: f)?.stop.id, "a")
        XCTAssertEqual(engine.next(stops: [area, poi()], fix: f)?.stop.id, "town")
        XCTAssertEqual(engine.candidates(stops: [area], fix: fix(4000, from: 90, course: 270)).count, 0, "already played")
    }

    func testAreaScriptHasNoIntro() {
        let area = Stop(id: "town", title: "Town", subtitle: "", category: .area, kind: .area,
                        location: center, radius: 5000, narration: "Welcome.")
        XCTAssertEqual(TriggerEngine().candidates(stops: [area], fix: fix(10, from: 0, course: nil, speed: 0)).first?.script, "Welcome.")
    }

    func testHeadsUpBeforeArrival() {
        var engine = TriggerEngine()
        // 1200 m out heading straight for it: beyond the 600 m reach, inside the teaser window.
        let first = engine.next(stops: [poi()], fix: fix(1200, from: 180, course: 0))
        XCTAssertEqual(first?.kind, .headsUp)
        XCTAssertEqual(first?.script, "In about three quarters of a mile, a place")
        // The teaser doesn't repeat, and the arrival still comes.
        XCTAssertNil(engine.next(stops: [poi()], fix: fix(1000, from: 180, course: 0, after: 10)))
        XCTAssertEqual(engine.next(stops: [poi()], fix: fix(500, from: 180, course: 0, after: 35))?.kind, .arrival)
    }

    func testHeadsUpsCanBeTurnedOff() {
        var settings = TriggerSettings()
        settings.headsUps = false
        XCTAssertTrue(TriggerEngine(settings: settings).candidates(stops: [poi()], fix: fix(1200, from: 180, course: 0)).isEmpty)
    }

    func testMutedCategory() {
        var settings = TriggerSettings()
        settings.mutedCategories = [.history]
        XCTAssertTrue(TriggerEngine(settings: settings).candidates(stops: [poi()], fix: fix(10, from: 0, course: nil)).isEmpty)
    }

    func testStillRelevant() {
        let engine = TriggerEngine()
        let trigger = engine.candidates(stops: [poi()], fix: fix(300, from: 180, course: 0))[0]
        XCTAssertTrue(engine.isStillRelevant(trigger, fix: fix(300, from: 0, course: 0)))
        XCTAssertFalse(engine.isStillRelevant(trigger, fix: fix(2000, from: 0, course: 0)))
    }

    func testForgetLetsItPlayAgain() {
        var engine = TriggerEngine()
        _ = engine.next(stops: [poi()], fix: fix(10, from: 0, course: nil))
        XCTAssertTrue(engine.hasPlayed("a"))
        engine.forget("a")
        XCTAssertFalse(engine.hasPlayed("a"))
    }
}
