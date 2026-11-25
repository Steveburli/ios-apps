import Foundation

/// Drives a pretend car along waypoints at a steady speed, producing the same fixes the GPS
/// would. Used by the in-app demo drive, the screenshots and the tests.
public struct RouteSimulator: Sendable {
    public let waypoints: [GeoPoint]
    /// Meters per second.
    public let speed: Double
    /// Distance from the start to each waypoint.
    let cumulative: [Double]

    public init(waypoints: [GeoPoint], speed: Double) {
        self.waypoints = waypoints
        self.speed = max(0.1, speed)
        var total = 0.0
        var list = [0.0]
        for i in waypoints.indices.dropFirst() {
            total += Geo.distance(waypoints[i - 1], waypoints[i])
            list.append(total)
        }
        cumulative = waypoints.isEmpty ? [] : list
    }

    public var totalDistance: Double { cumulative.last ?? 0 }
    public var duration: TimeInterval { totalDistance / speed }

    /// The fix `elapsed` seconds into the drive, or nil once it's over.
    public func fix(at elapsed: TimeInterval, start: Date) -> Fix? {
        guard waypoints.count >= 2, elapsed >= 0, elapsed <= duration else { return nil }
        let traveled = elapsed * speed
        var i = 1
        while i < cumulative.count - 1 && cumulative[i] < traveled { i += 1 }
        let a = waypoints[i - 1], b = waypoints[i]
        let legStart = cumulative[i - 1]
        let legLength = cumulative[i] - legStart
        let course = Geo.bearing(from: a, to: b)
        let along = legLength > 0 ? traveled - legStart : 0
        let point = Geo.destination(from: a, bearing: course, meters: along)
        return Fix(point: point, course: course, speed: speed, time: start.addingTimeInterval(elapsed))
    }
}
