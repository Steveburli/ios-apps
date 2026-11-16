import Foundation

/// A place the phone watches for Track timers, like Home or the gym.
public struct WatchedPlace: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var address: String
    public var coordinate: Coordinate
    /// How far from the pin still counts as being there, in meters. iPhones
    /// watch places loosely, so anything under about 100 meters fires late or not at all.
    public var radius: Double

    public static let defaultRadius: Double = 150
    public static let radiusChoices: [Double] = [100, 150, 250, 400]

    public init(id: String = newID(), name: String, address: String = "", coordinate: Coordinate,
                radius: Double = WatchedPlace.defaultRadius) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.radius = radius
    }

    private enum CodingKeys: String, CodingKey { case id, name, address, coordinate, radius }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  address: try c.decodeIfPresent(String.self, forKey: .address) ?? "",
                  coordinate: try c.decodeIfPresent(Coordinate.self, forKey: .coordinate) ?? Coordinate(latitude: 0, longitude: 0),
                  radius: try c.decodeIfPresent(Double.self, forKey: .radius) ?? WatchedPlace.defaultRadius)
    }
}

/// Arriving at a place or leaving it.
public enum PlaceCrossing: String, Codable, Sendable, CaseIterable {
    case arrive, leave

    public var verb: String { self == .arrive ? "arrive at" : "leave" }
    public var past: String { self == .arrive ? "Arrived at" : "Left" }
}

/// "Start Gym when I leave Home" or "Stop Gym when I leave the gym".
public struct PlaceRule: Codable, Identifiable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable, CaseIterable {
        case start, stop
    }

    public var id: String
    public var activityID: String
    public var action: Action
    public var crossing: PlaceCrossing
    public var placeID: String
    public var on: Bool

    public init(id: String = newID(), activityID: String, action: Action, crossing: PlaceCrossing, placeID: String, on: Bool = true) {
        self.id = id
        self.activityID = activityID
        self.action = action
        self.crossing = crossing
        self.placeID = placeID
        self.on = on
    }

    private enum CodingKeys: String, CodingKey { case id, activityID, action, crossing, placeID, on }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  activityID: try c.decodeIfPresent(String.self, forKey: .activityID) ?? "",
                  action: try c.decodeIfPresent(Action.self, forKey: .action) ?? .start,
                  crossing: try c.decodeIfPresent(PlaceCrossing.self, forKey: .crossing) ?? .leave,
                  placeID: try c.decodeIfPresent(String.self, forKey: .placeID) ?? "",
                  on: try c.decodeIfPresent(Bool.self, forKey: .on) ?? true)
    }
}

/// Something a place rule did, kept so it can be undone or checked later.
public struct PlaceFiring: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var ruleID: String
    public var at: Date
    public var action: PlaceRule.Action
    public var crossing: PlaceCrossing
    public var placeName: String
    public var title: String
    /// What was running before, for Undo: the timer the rule replaced or stopped.
    public var before: RunningTimer?
    /// The run the rule saved (the one it stopped), removed again by Undo.
    public var savedTimingID: String?
    public var undone = false

    public init(id: String = newID(), ruleID: String, at: Date, action: PlaceRule.Action, crossing: PlaceCrossing,
                placeName: String, title: String, before: RunningTimer?, savedTimingID: String?) {
        self.id = id
        self.ruleID = ruleID
        self.at = at
        self.action = action
        self.crossing = crossing
        self.placeName = placeName
        self.title = title
        self.before = before
        self.savedTimingID = savedTimingID
    }

    /// "Gym started: left Home".
    public var summary: String {
        "\(title) \(action == .start ? "started" : "stopped"): \(crossing.past.lowercased()) \(placeName)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, ruleID, at, action, crossing, placeName, title, before, savedTimingID, undone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  ruleID: try c.decodeIfPresent(String.self, forKey: .ruleID) ?? "",
                  at: try c.decodeIfPresent(Date.self, forKey: .at) ?? Date(),
                  action: try c.decodeIfPresent(PlaceRule.Action.self, forKey: .action) ?? .start,
                  crossing: try c.decodeIfPresent(PlaceCrossing.self, forKey: .crossing) ?? .leave,
                  placeName: try c.decodeIfPresent(String.self, forKey: .placeName) ?? "",
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  before: try c.decodeIfPresent(RunningTimer.self, forKey: .before),
                  savedTimingID: try c.decodeIfPresent(String.self, forKey: .savedTimingID))
        undone = try c.decodeIfPresent(Bool.self, forKey: .undone) ?? false
    }
}

/// Track timers that start and stop by place.
public struct PlaceTimers: Codable, Equatable, Sendable {
    public var places: [WatchedPlace] = []
    public var rules: [PlaceRule] = []
    /// Newest last.
    public var history: [PlaceFiring] = []
    /// When to ask "still running?" about a timer a rule started. Only counts
    /// while the timer that started at `checkTimerStart` is still running.
    public var checkAt: Date?
    public var checkTimerStart: Date?

    /// How long a rule-started timer runs before the app asks about it.
    public static let checkAfter: TimeInterval = 60 * 60
    public static let historyLimit = 100

    public init() {}

    private enum CodingKeys: String, CodingKey { case places, rules, history, checkAt, checkTimerStart }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        places = try c.decodeIfPresent([WatchedPlace].self, forKey: .places) ?? []
        rules = try c.decodeIfPresent([PlaceRule].self, forKey: .rules) ?? []
        history = try c.decodeIfPresent([PlaceFiring].self, forKey: .history) ?? []
        checkAt = try c.decodeIfPresent(Date.self, forKey: .checkAt)
        checkTimerStart = try c.decodeIfPresent(Date.self, forKey: .checkTimerStart)
    }

    public func place(_ id: String) -> WatchedPlace? {
        places.first { $0.id == id }
    }

    /// Places that at least one rule that's on needs watched.
    public var watchedPlaces: [WatchedPlace] {
        let needed = Set(rules.filter(\.on).map(\.placeID))
        return places.filter { needed.contains($0.id) }
    }
}

extension PlannerState {
    /// The "still running?" question, if one is due for the timer running now.
    public var placeCheckDue: Date? {
        guard let at = placeTimers.checkAt, let start = placeTimers.checkTimerStart,
              let running, running.startedAt == start else { return nil }
        return at
    }

    /// Runs the rules for crossing a place's edge. Returns what they did, newest last.
    @discardableResult
    public mutating func crossed(placeID: String, _ crossing: PlaceCrossing, at time: Date) -> [PlaceFiring] {
        guard let place = placeTimers.place(placeID) else { return [] }
        let rules = placeTimers.rules.filter { $0.on && $0.placeID == placeID && $0.crossing == crossing }
        // Stops first, so "stop Gym when I arrive home" and "start Chores when I
        // arrive home" both work on the same crossing.
        let ordered = rules.filter { $0.action == .stop } + rules.filter { $0.action == .start }
        var fired: [PlaceFiring] = []
        for rule in ordered {
            guard let activity = activity(rule.activityID) else { continue }
            let before = running
            switch rule.action {
            case .start:
                if running?.activityID == activity.id { continue }
                // A timer can't start before the one it replaces did.
                let start = max(time, running?.startedAt ?? time)
                let saved = startTimer(activityID: activity.id, title: activity.name, at: start)
                placeTimers.checkTimerStart = start
                placeTimers.checkAt = start.addingTimeInterval(PlaceTimers.checkAfter)
                fired.append(PlaceFiring(ruleID: rule.id, at: start, action: .start, crossing: crossing, placeName: place.name,
                                         title: activity.name, before: before, savedTimingID: saved?.id))
            case .stop:
                guard let current = running, current.activityID == activity.id else { continue }
                let saved = stopTimer(at: max(time, current.startedAt))
                fired.append(PlaceFiring(ruleID: rule.id, at: max(time, current.startedAt), action: .stop, crossing: crossing,
                                         placeName: place.name, title: activity.name, before: before, savedTimingID: saved?.id))
            }
        }
        placeTimers.history.append(contentsOf: fired)
        if placeTimers.history.count > PlaceTimers.historyLimit {
            placeTimers.history.removeFirst(placeTimers.history.count - PlaceTimers.historyLimit)
        }
        return fired
    }

    /// Whether Undo still makes sense: nothing else has changed the stopwatch since.
    public func canUndo(_ firing: PlaceFiring) -> Bool {
        guard !firing.undone, placeTimers.history.last(where: { !$0.undone })?.id == firing.id else { return false }
        switch firing.action {
        case .start:
            return running?.title == firing.title && running?.startedAt == firing.at
        case .stop:
            return running == nil
        }
    }

    /// Puts the stopwatch back the way it was before a rule fired.
    @discardableResult
    public mutating func undo(firingID: String) -> Bool {
        guard let index = placeTimers.history.firstIndex(where: { $0.id == firingID }),
              canUndo(placeTimers.history[index]) else { return false }
        let firing = placeTimers.history[index]
        if let saved = firing.savedTimingID {
            timings.removeAll { $0.id == saved }
        }
        running = firing.before
        placeTimers.history[index].undone = true
        if firing.action == .start, placeTimers.checkTimerStart == firing.at {
            placeTimers.checkAt = nil
            placeTimers.checkTimerStart = nil
        }
        return true
    }

    /// "Keep going": ask again later.
    public mutating func postponePlaceCheck(from now: Date) {
        guard placeCheckDue != nil else { return }
        placeTimers.checkAt = now.addingTimeInterval(PlaceTimers.checkAfter)
    }

    public mutating func deleteWatchedPlace(_ id: String) {
        placeTimers.places.removeAll { $0.id == id }
        placeTimers.rules.removeAll { $0.placeID == id }
    }
}
