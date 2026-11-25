import Foundation

/// A latitude and longitude in degrees. Foundation-only so the logic can be tested
/// without Core Location; the app converts to and from `CLLocationCoordinate2D`.
public struct GeoPoint: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Great-circle math on a spherical Earth. Good to well under a meter at tour scales.
public enum Geo {
    public static let earthRadius = 6_371_000.0

    static func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func deg(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Meters between two points (haversine).
    public static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let dLat = rad(b.lat - a.lat)
        let dLon = rad(b.lon - a.lon)
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(rad(a.lat)) * cos(rad(b.lat)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Initial compass bearing from `a` to `b`, 0..<360, where 0 is north and 90 is east.
    public static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let lat1 = rad(a.lat), lat2 = rad(b.lat)
        let dLon = rad(b.lon - a.lon)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalize(deg(atan2(y, x)))
    }

    /// The point `meters` away from `start` along `bearing`.
    public static func destination(from start: GeoPoint, bearing: Double, meters: Double) -> GeoPoint {
        let delta = meters / earthRadius
        let theta = rad(bearing)
        let lat1 = rad(start.lat), lon1 = rad(start.lon)
        let lat2 = asin(sin(lat1) * cos(delta) + cos(lat1) * sin(delta) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(delta) * cos(lat1), cos(delta) - sin(lat1) * sin(lat2))
        return GeoPoint(lat: deg(lat2), lon: deg(lon2))
    }

    /// Any angle folded into 0..<360.
    public static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Signed turn from `from` to `to`, in -180...180. Positive means clockwise (to the right).
    public static func signedDelta(from: Double, to: Double) -> Double {
        var d = normalize(to) - normalize(from)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    /// Unsigned difference between two headings, 0...180.
    public static func angleBetween(_ a: Double, _ b: Double) -> Double {
        abs(signedDelta(from: a, to: b))
    }

    /// An eight-point compass word for a heading, as a narrator would say it.
    public static func compassWord(_ heading: Double) -> String {
        let words = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let index = Int((normalize(heading) + 22.5) / 45) % 8
        return words[index]
    }
}

/// Where a stop sits relative to the direction of travel.
public enum RelativeSide: String, Codable, Sendable {
    case ahead, left, right, behind

    /// Ahead within ±25°, behind beyond ±155°, else left or right.
    public init(course: Double, bearingToTarget: Double) {
        let d = Geo.signedDelta(from: course, to: bearingToTarget)
        switch abs(d) {
        case ..<25: self = .ahead
        case 155...: self = .behind
        default: self = d > 0 ? .right : .left
        }
    }

    /// "on your left", "straight ahead" …
    public var phrase: String {
        switch self {
        case .ahead: "straight ahead"
        case .left: "on your left"
        case .right: "on your right"
        case .behind: "just behind you"
        }
    }
}
