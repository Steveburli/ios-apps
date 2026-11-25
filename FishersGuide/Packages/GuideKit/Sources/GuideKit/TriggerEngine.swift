import Foundation

/// One location reading, as the engine sees it.
public struct Fix: Sendable, Equatable {
    public var point: GeoPoint
    /// Direction of travel in degrees (0 = north), or nil when unknown.
    public var course: Double?
    /// Meters per second, 0 or more.
    public var speed: Double
    public var time: Date

    public init(point: GeoPoint, course: Double?, speed: Double, time: Date) {
        self.point = point
        self.course = course
        self.speed = max(0, speed)
        self.time = time
    }
}

/// The knobs that decide when a stop starts talking.
public struct TriggerSettings: Codable, Equatable, Sendable {
    /// Seconds of travel to look ahead. At 45 mph (20 m/s) 20 s starts a story 400 m early,
    /// so it's underway as the place comes into view.
    public var leadSeconds: Double = 20
    /// The lead never adds more than this many meters.
    public var maxLead: Double = 450
    /// How far off the direction of travel (degrees) a stop can be and still count as "ahead".
    public var headingTolerance: Double = 60
    /// Below this speed (m/s, about 4.5 mph) the course is too noisy to trust.
    public var minCourseSpeed: Double = 2
    /// A stop won't repeat for this long (seconds) once heard.
    public var cooldown: TimeInterval = 6 * 3600
    /// Play the short "coming up" teaser before a stop.
    public var headsUps: Bool = true
    /// How far beyond the trigger circle (meters) a teaser can fire.
    public var headsUpDistance: Double = 1200
    /// Categories the person turned off.
    public var mutedCategories: Set<StopCategory> = []

    public init() {}
}

/// Something for the narrator to say.
public struct Trigger: Equatable, Sendable {
    public enum Kind: String, Sendable { case arrival, headsUp }

    public var stop: Stop
    public var kind: Kind
    public var side: RelativeSide?
    public var distance: Double
    /// Everything to speak, intro included.
    public var script: String
}

/// Decides which stop (if any) to narrate from a location fix: how close you are, which
/// way you're going, which side of the road it's on, and what you've already heard.
/// It's a value type so the app can save it and tests can drive it fix by fix.
public struct TriggerEngine: Sendable {
    public var settings: TriggerSettings
    /// Stop id → when its full story last played.
    public private(set) var played: [String: Date]
    /// Stop id → when its teaser last played.
    public private(set) var teased: [String: Date]

    public init(settings: TriggerSettings = TriggerSettings(), played: [String: Date] = [:], teased: [String: Date] = [:]) {
        self.settings = settings
        self.played = played
        self.teased = teased
    }

    // MARK: - Asking

    /// The best thing to say now, marking it as heard. Arrivals beat teasers.
    public mutating func next(stops: [Stop], fix: Fix) -> Trigger? {
        guard let best = candidates(stops: stops, fix: fix).first else { return nil }
        switch best.kind {
        case .arrival: played[best.stop.id] = fix.time
        case .headsUp: teased[best.stop.id] = fix.time
        }
        return best
    }

    /// Everything that could play now, best first. Doesn't change anything.
    public func candidates(stops: [Stop], fix: Fix) -> [Trigger] {
        let course = usableCourse(fix)
        var arrivals: [(Trigger, Double)] = []
        var teasers: [(Trigger, Double)] = []

        for stop in stops where !settings.mutedCategories.contains(stop.category) {
            let distance = Geo.distance(fix.point, stop.location)
            let bearing = Geo.bearing(from: fix.point, to: stop.location)
            let side = course.map { RelativeSide(course: $0, bearingToTarget: bearing) }

            if stop.kind == .area {
                guard !isCooling(stop.id, in: played, at: fix.time), distance <= stop.radius else { continue }
                let trigger = Trigger(stop: stop, kind: .arrival, side: nil, distance: distance,
                                      script: Script.arrival(stop, side: nil, distance: distance, course: course))
                arrivals.append((trigger, 1 + distance / stop.radius)) // areas rank after any POI
                continue
            }

            guard !isCooling(stop.id, in: played, at: fix.time) else { continue }
            guard approachAllows(stop, course: course, distance: distance) else { continue }

            var reach = stop.radius
            if let course {
                let off = Geo.angleBetween(course, bearing)
                // Already driving away from it and most of the way out of the circle: too late.
                if off > 110 && distance > stop.radius * 0.6 { continue }
                if off <= settings.headingTolerance {
                    reach += min(fix.speed * settings.leadSeconds, settings.maxLead)
                }
                if distance <= reach {
                    let trigger = Trigger(stop: stop, kind: .arrival, side: side, distance: distance,
                                          script: Script.arrival(stop, side: side, distance: distance, course: course))
                    arrivals.append((trigger, distance / reach))
                } else if settings.headsUps, let teaser = stop.teaser, off <= 35,
                          distance <= reach + settings.headsUpDistance,
                          !isCooling(stop.id, in: teased, at: fix.time) {
                    let trigger = Trigger(stop: stop, kind: .headsUp, side: side, distance: distance,
                                          script: Script.headsUp(teaser, distance: distance))
                    teasers.append((trigger, distance))
                }
            } else if distance <= reach {
                let trigger = Trigger(stop: stop, kind: .arrival, side: nil, distance: distance,
                                      script: Script.arrival(stop, side: nil, distance: distance, course: nil))
                arrivals.append((trigger, distance / reach))
            }
        }

        func ranked(_ list: [(Trigger, Double)]) -> [Trigger] {
            list.sorted { a, b in
                let aArea = a.0.stop.kind == .area, bArea = b.0.stop.kind == .area
                if aArea != bArea { return !aArea }
                if a.0.stop.priority != b.0.stop.priority { return a.0.stop.priority > b.0.stop.priority }
                return a.1 < b.1
            }.map(\.0)
        }
        return ranked(arrivals) + ranked(teasers)
    }

    /// Whether a trigger chosen a while ago (say, while another story was playing) is still
    /// worth playing from where you are now.
    public func isStillRelevant(_ trigger: Trigger, fix: Fix) -> Bool {
        let distance = Geo.distance(fix.point, trigger.stop.location)
        switch trigger.kind {
        case .headsUp:
            return distance <= trigger.distance + 50 && distance > trigger.stop.radius
        case .arrival:
            if trigger.stop.kind == .area { return distance <= trigger.stop.radius }
            return distance <= trigger.stop.radius * 2 + settings.maxLead
        }
    }

    // MARK: - Telling

    public mutating func markPlayed(_ id: String, at time: Date) {
        played[id] = time
    }

    /// Lets a stop play again (it was skipped before it really started, say).
    public mutating func forget(_ id: String) {
        played[id] = nil
        teased[id] = nil
    }

    public mutating func resetHistory() {
        played = [:]
        teased = [:]
    }

    public func hasPlayed(_ id: String) -> Bool {
        played[id] != nil
    }

    // MARK: - Rules

    func usableCourse(_ fix: Fix) -> Double? {
        guard let course = fix.course, course >= 0, fix.speed >= settings.minCourseSpeed else { return nil }
        return Geo.normalize(course)
    }

    func isCooling(_ id: String, in log: [String: Date], at time: Date) -> Bool {
        guard let last = log[id] else { return false }
        return time.timeIntervalSince(last) < settings.cooldown
    }

    /// A stop with approach headings plays only while traveling one of them. Standing still
    /// inside its circle also counts, so a parked visitor still hears it.
    func approachAllows(_ stop: Stop, course: Double?, distance: Double) -> Bool {
        guard !stop.approach.isEmpty else { return true }
        guard let course else { return distance <= stop.radius }
        return stop.approach.contains { $0.contains(course) }
    }
}

/// The words around a stop's story.
public enum Script {
    public static func arrival(_ stop: Stop, side: RelativeSide?, distance: Double, course: Double?) -> String {
        let story = stop.narration(forCourse: course)
        if stop.kind == .area { return story }
        let intro: String
        switch side {
        case .left?, .right?:
            intro = distance > stop.radius * 0.4 ? "Coming up \(side!.phrase): \(stop.title)." : "\(stop.title), \(side!.phrase)."
        case .ahead?:
            intro = "Just ahead: \(stop.title)."
        case .behind?, nil:
            intro = "You're near \(stop.title)."
        }
        return intro + " " + story
    }

    public static func headsUp(_ teaser: String, distance: Double) -> String {
        "In about \(distanceWords(distance)), \(teaser)"
    }

    /// Spoken distances in US units: "a few hundred feet", "half a mile", "2 miles".
    public static func distanceWords(_ meters: Double) -> String {
        let miles = meters / 1609.344
        if miles < 0.15 { return "a few hundred feet" }
        let quarters = Int((miles * 4).rounded())
        switch quarters {
        case 0, 1: return "a quarter mile"
        case 2: return "half a mile"
        case 3: return "three quarters of a mile"
        case 4: return "a mile"
        case 6: return "a mile and a half"
        default:
            let whole = Int(miles.rounded())
            return whole == 1 ? "a mile" : "\(whole) miles"
        }
    }
}
