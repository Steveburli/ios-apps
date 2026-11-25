import XCTest
@testable import GuideKit

final class TourTests: XCTestCase {
    func testBundledTourLoads() throws {
        let tour = try Tour.bundledFishers()
        XCTAssertEqual(tour.id, "fishers")
        XCTAssertGreaterThanOrEqual(tour.stops.count, 10)
        XCTAssertGreaterThanOrEqual(tour.demoRoute.count, 2)
    }

    func testStopsAreSane() throws {
        let tour = try Tour.bundledFishers()
        XCTAssertEqual(Set(tour.stops.map(\.id)).count, tour.stops.count, "ids must be unique")
        for stop in tour.stops {
            // Everything sits in and around Hamilton County, Indiana.
            XCTAssertTrue((39.85...40.25).contains(stop.location.lat), stop.id)
            XCTAssertTrue((-86.25 ... -85.80).contains(stop.location.lon), stop.id)
            XCTAssertGreaterThan(stop.radius, 50, stop.id)
            XCTAssertGreaterThan(stop.narration.count, 100, stop.id)
            XCTAssertEqual(stop.kind == .area, stop.category == .area, stop.id)
        }
    }

    func testOptionalFieldsDefault() throws {
        let json = """
        {"id":"x","title":"X","category":"nature","location":{"lat":40,"lon":-86},"radius":100,"narration":"Hi."}
        """
        let stop = try JSONDecoder().decode(Stop.self, from: Data(json.utf8))
        XCTAssertEqual(stop.kind, .poi)
        XCTAssertEqual(stop.priority, 0)
        XCTAssertTrue(stop.approach.isEmpty)
        XCTAssertNil(stop.teaser)
    }

    func testDemoDriveHearsMostStops() throws {
        let tour = try Tour.bundledFishers()
        let sim = RouteSimulator(waypoints: tour.demoRoute, speed: 22)
        var engine = TriggerEngine()
        var heard: [String] = []
        var t: TimeInterval = 0
        while let f = sim.fix(at: t, start: Date(timeIntervalSince1970: 0)) {
            if let trigger = engine.next(stops: tour.stops, fix: f), trigger.kind == .arrival {
                heard.append(trigger.stop.id)
            }
            t += 2
        }
        for id in ["fishers-welcome", "fishers-municipal", "conner-prairie", "courthouse-square", "potters-bridge", "ruoff", "geist"] {
            XCTAssertTrue(heard.contains(id), "demo drive should reach \(id); heard \(heard)")
        }
    }
}

final class RouteSimulatorTests: XCTestCase {
    func testWalksTheRoute() {
        let a = GeoPoint(lat: 40, lon: -86)
        let b = Geo.destination(from: a, bearing: 0, meters: 1000)
        let c = Geo.destination(from: b, bearing: 90, meters: 1000)
        let sim = RouteSimulator(waypoints: [a, b, c], speed: 10)
        XCTAssertEqual(sim.totalDistance, 2000, accuracy: 1)
        XCTAssertEqual(sim.duration, 200, accuracy: 0.1)

        let start = Date()
        let mid = sim.fix(at: 50, start: start)!
        XCTAssertEqual(Geo.distance(a, mid.point), 500, accuracy: 1)
        XCTAssertEqual(mid.course!, 0, accuracy: 0.5)

        let second = sim.fix(at: 150, start: start)!
        XCTAssertEqual(second.course!, 90, accuracy: 1)
        XCTAssertEqual(Geo.distance(b, second.point), 500, accuracy: 1)

        XCTAssertNil(sim.fix(at: 201, start: start))
    }
}
