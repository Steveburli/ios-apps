import XCTest
@testable import GuideKit

final class GeoTests: XCTestCase {
    let cityHall = GeoPoint(lat: 39.95865, lon: -86.01704)
    let courthouse = GeoPoint(lat: 40.04583, lon: -86.01417)

    func testDistanceCityHallToCourthouse() {
        // About 9.7 km due north-ish.
        let d = Geo.distance(cityHall, courthouse)
        XCTAssertEqual(d, 9_700, accuracy: 100)
    }

    func testBearingCardinals() {
        let north = Geo.destination(from: cityHall, bearing: 0, meters: 1000)
        let east = Geo.destination(from: cityHall, bearing: 90, meters: 1000)
        XCTAssertEqual(Geo.bearing(from: cityHall, to: north), 0, accuracy: 0.5)
        XCTAssertEqual(Geo.bearing(from: cityHall, to: east), 90, accuracy: 0.5)
        XCTAssertEqual(Geo.bearing(from: north, to: cityHall), 180, accuracy: 0.5)
    }

    func testDestinationRoundTrip() {
        let p = Geo.destination(from: cityHall, bearing: 37, meters: 2500)
        XCTAssertEqual(Geo.distance(cityHall, p), 2500, accuracy: 1)
        XCTAssertEqual(Geo.bearing(from: cityHall, to: p), 37, accuracy: 0.5)
    }

    func testAngles() {
        XCTAssertEqual(Geo.normalize(-90), 270)
        XCTAssertEqual(Geo.normalize(725), 5)
        XCTAssertEqual(Geo.signedDelta(from: 350, to: 10), 20)
        XCTAssertEqual(Geo.signedDelta(from: 10, to: 350), -20)
        XCTAssertEqual(Geo.angleBetween(90, 270), 180)
    }

    func testRelativeSide() {
        XCTAssertEqual(RelativeSide(course: 0, bearingToTarget: 5), .ahead)
        XCTAssertEqual(RelativeSide(course: 0, bearingToTarget: 80), .right)
        XCTAssertEqual(RelativeSide(course: 0, bearingToTarget: 280), .left)
        XCTAssertEqual(RelativeSide(course: 0, bearingToTarget: 180), .behind)
        XCTAssertEqual(RelativeSide(course: 350, bearingToTarget: 60), .right)
    }

    func testHeadingRangeWrapsThroughNorth() {
        let north = HeadingRange(from: 300, to: 60)
        XCTAssertTrue(north.contains(0))
        XCTAssertTrue(north.contains(330))
        XCTAssertTrue(north.contains(45))
        XCTAssertFalse(north.contains(180))
        let east = HeadingRange(from: 30, to: 150)
        XCTAssertTrue(east.contains(90))
        XCTAssertFalse(east.contains(200))
    }

    func testCompassWords() {
        XCTAssertEqual(Geo.compassWord(0), "north")
        XCTAssertEqual(Geo.compassWord(359), "north")
        XCTAssertEqual(Geo.compassWord(95), "east")
        XCTAssertEqual(Geo.compassWord(225), "southwest")
    }

    func testDistanceWords() {
        XCTAssertEqual(Script.distanceWords(100), "a few hundred feet")
        XCTAssertEqual(Script.distanceWords(800), "half a mile")
        XCTAssertEqual(Script.distanceWords(1609), "a mile")
        XCTAssertEqual(Script.distanceWords(5000), "3 miles")
    }
}
