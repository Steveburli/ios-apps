import Foundation

// Trip mode: one day out (a birthday, a city visit) planned stop by stop. Fixed
// stops (a show, check-in, a dinner booking) keep their time; flexible stops
// flow around them; a wish list holds the rest. New in the app only, not in
// the web app.

/// What kind of place a stop is. Each kind starts with its own time spent there.
public enum StopKind: String, Codable, CaseIterable, Sendable {
    case meal, sight, shop, show, stay, other

    public var label: String {
        switch self {
        case .meal: return "Meal"
        case .sight: return "Sight"
        case .shop: return "Shop"
        case .show: return "Show"
        case .stay: return "Hotel"
        case .other: return "Other"
        }
    }

    /// The starting "time spent here", which you can change on each stop.
    public var defaultMinutes: Int {
        switch self {
        case .meal: return 75
        case .sight: return 60
        case .shop: return 30
        case .show: return 120
        case .stay: return 20
        case .other: return 30
        }
    }
}

public enum TravelMode: String, Codable, Sendable {
    case walk, drive
}

/// How important a flexible stop is: 3 is top, 1 is "if there's time".
public enum StopPriority {
    public static let top = 3
    public static let want = 2
    public static let maybe = 1

    /// The catch-up plan adds these up, so one top stop outweighs two "want" stops.
    static func weight(_ priority: Int) -> Int {
        switch priority {
        case 3...: return 9
        case 2: return 3
        default: return 1
        }
    }
}

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Rounded to about 10 meters, so travel times can be remembered per pair of places.
    public var key: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    /// Kilometers along the ground.
    public func distance(to other: Coordinate) -> Double {
        let r = 6371.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}

public struct Trip: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var day: CalendarDay
    /// When you expect to get there, in minutes after midnight.
    public var startMinute: Int
    /// When the day should be over.
    public var endMinute: Int
    /// Set by "We're here": the plan starts from when you really arrived.
    public var arrivedMinute: Int?
    /// Set by "We're off schedule": the plan picks up again at `resumeStopID` from this time.
    public var resumeMinute: Int?
    public var resumeStopID: String?
    /// Walk when it takes this long or less, otherwise drive.
    public var walkLimit: Int
    public var createdAt: Date
    public var isExample = false

    public init(id: String = newID(), name: String, day: CalendarDay, startMinute: Int = 600, endMinute: Int = 1320,
                walkLimit: Int = 30, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.day = day
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.walkLimit = walkLimit
        self.createdAt = createdAt
    }

    /// Where the day's plan starts from.
    public var planStart: Int {
        arrivedMinute ?? startMinute
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, day, startMinute, endMinute, arrivedMinute, resumeMinute, resumeStopID, walkLimit, createdAt, isExample
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? newID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Trip"
        day = try c.decodeIfPresent(CalendarDay.self, forKey: .day) ?? CalendarDay(year: 2026, month: 1, day: 1)
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute) ?? 600
        endMinute = try c.decodeIfPresent(Int.self, forKey: .endMinute) ?? 1320
        arrivedMinute = try c.decodeIfPresent(Int.self, forKey: .arrivedMinute)
        resumeMinute = try c.decodeIfPresent(Int.self, forKey: .resumeMinute)
        resumeStopID = try c.decodeIfPresent(String.self, forKey: .resumeStopID)
        walkLimit = try c.decodeIfPresent(Int.self, forKey: .walkLimit) ?? 30
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
    }
}

public struct TripStop: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var tripID: String
    public var title: String
    public var address: String
    public var coordinate: Coordinate?
    public var kind: StopKind
    /// Time spent here, in minutes.
    public var stayMinutes: Int
    /// A fixed stop's time (minutes after midnight). Nil for flexible stops.
    public var fixedMinute: Int?
    public var priority: Int
    /// On the day's plan, or waiting on the wish list.
    public var onDay: Bool
    /// Position on the day or the wish list.
    public var order: Double
    public var done: Bool
    public var note: String

    public init(id: String = newID(), tripID: String, title: String, address: String = "", coordinate: Coordinate? = nil,
                kind: StopKind = .other, stayMinutes: Int? = nil, fixedMinute: Int? = nil, priority: Int = StopPriority.want,
                onDay: Bool = true, order: Double = 0, done: Bool = false, note: String = "") {
        self.id = id
        self.tripID = tripID
        self.title = title
        self.address = address
        self.coordinate = coordinate
        self.kind = kind
        self.stayMinutes = max(0, stayMinutes ?? kind.defaultMinutes)
        self.fixedMinute = fixedMinute
        self.priority = priority
        self.onDay = onDay
        self.order = order
        self.done = done
        self.note = note
    }

    public var isFixed: Bool {
        fixedMinute != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, tripID, title, address, coordinate, kind, stayMinutes, fixedMinute, priority, onDay, order, done, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? newID()
        tripID = try c.decodeIfPresent(String.self, forKey: .tripID) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        coordinate = try c.decodeIfPresent(Coordinate.self, forKey: .coordinate)
        kind = (try? c.decodeIfPresent(StopKind.self, forKey: .kind)) ?? .other
        stayMinutes = try c.decodeIfPresent(Int.self, forKey: .stayMinutes) ?? kind.defaultMinutes
        fixedMinute = try c.decodeIfPresent(Int.self, forKey: .fixedMinute)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? StopPriority.want
        onDay = try c.decodeIfPresent(Bool.self, forKey: .onDay) ?? true
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// Travel time between two places, both ways of getting there.
public struct Leg: Codable, Equatable, Sendable {
    public var walkMinutes: Int
    public var driveMinutes: Int
    /// True when worked out from the straight-line distance instead of Apple Maps.
    public var isEstimate: Bool

    public init(walkMinutes: Int, driveMinutes: Int, isEstimate: Bool = false) {
        self.walkMinutes = max(1, walkMinutes)
        self.driveMinutes = max(1, driveMinutes)
        self.isEstimate = isEstimate
    }

    public func mode(walkLimit: Int) -> TravelMode {
        walkMinutes <= walkLimit ? .walk : .drive
    }

    public func minutes(walkLimit: Int) -> Int {
        mode(walkLimit: walkLimit) == .walk ? walkMinutes : driveMinutes
    }

    /// A rough guess from the straight-line distance, for when Apple Maps can't be asked:
    /// streets add about a quarter, people walk about 4.8 km/h, city driving averages
    /// about 35 km/h, and parking takes about 5 minutes.
    public static func estimate(from a: Coordinate, to b: Coordinate) -> Leg {
        let km = a.distance(to: b) * 1.25
        let walk = Int((km / 4.8 * 60).rounded())
        let drive = km < 0.05 ? 1 : Int((km / 35 * 60).rounded()) + 5
        return Leg(walkMinutes: walk, driveMinutes: drive, isEstimate: true)
    }

    public static func key(from a: Coordinate, to b: Coordinate) -> String {
        a.key + ">" + b.key
    }
}

// MARK: - The day's schedule

public struct ScheduledStop: Equatable, Sendable {
    public var stop: TripStop
    /// How you get here from the stop before. Nil for the first stop, or when either place has no address.
    public var travelMode: TravelMode?
    public var travelMinutes: Int
    public var travelIsEstimate: Bool
    public var arrive: Int
    /// When the stop starts: a fixed stop waits for its time.
    public var start: Int
    public var leave: Int
    /// Minutes spent waiting for a fixed stop.
    public var wait: Int
    /// How late you'd be for a fixed stop.
    public var lateBy: Int
}

/// A way to stop being late for a fixed stop.
public enum ScheduleFix: Equatable, Sendable {
    /// Put this stop back on the wish list.
    case drop(stopID: String)
    /// Do this stop after the fixed one instead.
    case moveAfter(stopID: String, fixedID: String)

    public var stopID: String {
        switch self {
        case .drop(let id): return id
        case .moveAfter(let id, _): return id
        }
    }
}

public struct LateWarning: Equatable, Sendable {
    public var fixedID: String
    public var lateBy: Int
    /// Fixes that get you there on time, the least important stop first. Empty when
    /// no single move is enough.
    public var fixes: [ScheduleFix]
}

public struct TripSchedule: Equatable, Sendable {
    public var items: [ScheduledStop]
    public var start: Int
    public var finish: Int
    /// Minutes past the trip's end time, or 0.
    public var overEnd: Int
    public var warnings: [LateWarning]

    public func item(_ id: String) -> ScheduledStop? {
        items.first { $0.stop.id == id }
    }
}

/// Plans one trip. `legs` holds travel times from Apple Maps by `Leg.key`; any
/// pair missing there is estimated from the straight-line distance.
public struct TripPlanner: Sendable {
    public var trip: Trip
    public var stops: [TripStop]
    public var legs: [String: Leg]

    public init(trip: Trip, stops: [TripStop], legs: [String: Leg] = [:]) {
        self.trip = trip
        self.stops = stops.filter { $0.tripID == trip.id }
        self.legs = legs
    }

    /// The day's stops in order.
    public var dayStops: [TripStop] {
        stops.filter(\.onDay).stableSorted { $0.order < $1.order }
    }

    /// The wish list: top priority first, then in the order you added them.
    public var wishList: [TripStop] {
        stops.filter { !$0.onDay }.stableSorted { a, b in
            a.priority != b.priority ? a.priority > b.priority : a.order < b.order
        }
    }

    public func leg(from a: TripStop, to b: TripStop) -> Leg? {
        guard let from = a.coordinate, let to = b.coordinate else { return nil }
        return leg(from: from, to: to)
    }

    public func leg(from a: Coordinate, to b: Coordinate) -> Leg {
        legs[Leg.key(from: a, to: b)] ?? Leg.estimate(from: a, to: b)
    }

    public func schedule() -> TripSchedule {
        let items = Self.lay(dayStops, trip: trip, planner: self)
        var warnings: [LateWarning] = []
        for item in items where item.lateBy > 0 {
            warnings.append(LateWarning(fixedID: item.stop.id, lateBy: item.lateBy, fixes: fixes(forLate: item.stop.id)))
        }
        let finish = items.last?.leave ?? trip.planStart
        return TripSchedule(items: items, start: trip.planStart, finish: finish, overEnd: max(0, finish - trip.endMinute),
                            warnings: warnings)
    }

    /// Works out arrival times: the previous stop's leave time plus travel, with
    /// fixed stops waiting for their time.
    static func lay(_ ordered: [TripStop], trip: Trip, planner: TripPlanner) -> [ScheduledStop] {
        var clock = trip.planStart
        var previous: TripStop?
        var items: [ScheduledStop] = []
        for stop in ordered {
            var mode: TravelMode?
            var travel = 0
            var estimate = false
            if let previous, let leg = planner.leg(from: previous, to: stop) {
                mode = leg.mode(walkLimit: trip.walkLimit)
                travel = leg.minutes(walkLimit: trip.walkLimit)
                estimate = leg.isEstimate
            }
            var arrive = clock + travel
            // After "We're off schedule", the new plan starts from when you asked.
            if let resume = trip.resumeMinute, stop.id == trip.resumeStopID {
                arrive = resume + travel
            }
            var start = arrive
            var wait = 0
            var late = 0
            if let fixed = stop.fixedMinute {
                if arrive <= fixed {
                    wait = fixed - arrive
                    start = fixed
                } else {
                    late = arrive - fixed
                }
            }
            let leave = start + stop.stayMinutes
            items.append(ScheduledStop(stop: stop, travelMode: mode, travelMinutes: travel, travelIsEstimate: estimate,
                                       arrive: arrive, start: start, leave: leave, wait: wait, lateBy: late))
            clock = leave
            previous = stop
        }
        return items
    }

    /// Flexible stops between the fixed stop before and this one that, moved or
    /// dropped on their own, get you there on time.
    func fixes(forLate fixedID: String) -> [ScheduleFix] {
        let day = dayStops
        guard let index = day.firstIndex(where: { $0.id == fixedID }) else { return [] }
        var from = index - 1
        while from >= 0, !day[from].isFixed { from -= 1 }
        let candidates = day[(from + 1)..<index].filter { !$0.done && !$0.isFixed }
            .stableSorted { a, b in a.priority < b.priority }
        var result: [ScheduleFix] = []
        for stop in candidates {
            var without = day
            without.removeAll { $0.id == stop.id }
            let laid = Self.lay(without, trip: trip, planner: self)
            guard let fixed = laid.first(where: { $0.stop.id == fixedID }), fixed.lateBy == 0 else { continue }
            result.append(.drop(stopID: stop.id))
            // Moving it after the fixed stop only helps if there's a stop to come back from.
            result.append(.moveAfter(stopID: stop.id, fixedID: fixedID))
        }
        return result
    }

    // MARK: Changes

    /// Puts the day's fixed stops back in time order, keeping the flexible stops where they were.
    public static func sortingFixed(_ day: [TripStop]) -> [TripStop] {
        let slots = day.indices.filter { day[$0].isFixed }
        let fixed = slots.map { day[$0] }.stableSorted { ($0.fixedMinute ?? 0) < ($1.fixedMinute ?? 0) }
        var result = day
        for (slot, stop) in zip(slots, fixed) { result[slot] = stop }
        return renumbered(result)
    }

    /// Gives stops orders 1, 2, 3... in the order given.
    public static func renumbered(_ list: [TripStop]) -> [TripStop] {
        list.enumerated().map { index, stop in
            var stop = stop
            stop.order = Double(index + 1)
            return stop
        }
    }

    /// The day's stops after a fix. Returns only the stops that changed.
    public func applying(_ fix: ScheduleFix) -> [TripStop] {
        var day = dayStops
        guard let index = day.firstIndex(where: { $0.id == fix.stopID }) else { return [] }
        var moved = day.remove(at: index)
        switch fix {
        case .drop:
            moved.onDay = false
            moved.order = (wishList.map(\.order).max() ?? 0) + 1
            return Self.renumbered(day) + [moved]
        case .moveAfter(_, let fixedID):
            let after = (day.firstIndex { $0.id == fixedID } ?? day.count - 1) + 1
            day.insert(moved, at: min(after, day.count))
            return Self.renumbered(day)
        }
    }

    // MARK: Catch-up

    /// What "We're off schedule" suggests.
    public struct CatchUp: Equatable, Sendable {
        public struct Skipped: Equatable, Sendable {
            public var stop: TripStop
            /// Time it would take on its own, with travel there and on to the next fixed stop.
            public var needs: Int
            /// True when it doesn't fit even on its own.
            public var tooLong: Bool
        }

        public var now: Int
        /// The next fixed stop, or nil when the rest of the day is open.
        public var next: TripStop?
        /// When you have to be at `next` (or the trip's end time).
        public var deadline: Int
        public var available: Int
        /// What to do, in order.
        public var picks: [TripStop]
        /// The times those picks would have, then the next fixed stop.
        public var plan: [ScheduledStop]
        /// Minutes to spare before the deadline.
        public var spare: Int
        /// More important stops that didn't make it, and why.
        public var skipped: [Skipped]
        /// True when you're already late for `next`.
        public var lateForNext: Bool
    }

    /// From where you are now, finds the most important flexible stops that fit
    /// before the next fixed stop, in the quickest order. `here` is where you
    /// are; without it, the last finished stop is used.
    public func catchUp(now: Int, here: Coordinate?) -> CatchUp {
        let day = dayStops
        let next = day.first { !$0.done && $0.isFixed }
        let deadline = next?.fixedMinute ?? trip.endMinute
        let available = max(0, deadline - now)
        let start = here ?? day.last(where: \.done)?.coordinate

        // Flexible stops still to do before the next fixed one, then the wish list.
        let nextIndex = next.flatMap { n in day.firstIndex { $0.id == n.id } } ?? day.count
        var candidates = day[..<nextIndex].filter { !$0.done && !$0.isFixed }
        candidates += wishList.filter { !$0.done && !$0.isFixed }
        let pool = Array(candidates.stableSorted { $0.priority > $1.priority }.prefix(9))

        func travel(_ a: Coordinate?, _ b: Coordinate?) -> Int {
            guard let a, let b else { return 0 }
            return leg(from: a, to: b).minutes(walkLimit: trip.walkLimit)
        }

        func needs(_ order: [TripStop]) -> Int {
            var total = 0
            var at = start
            for stop in order {
                total += travel(at, stop.coordinate) + stop.stayMinutes
                at = stop.coordinate ?? at
            }
            if let next { total += travel(at, next.coordinate) }
            return total
        }

        var best: [TripStop] = []
        var bestScore = 0
        var bestNeeds = Int.max
        let maxSize = min(4, pool.count)
        if maxSize > 0 {
            for size in 1...maxSize {
                for subset in Self.combinations(of: pool.count, choosing: size) {
                    let chosen = subset.map { pool[$0] }
                    let score = chosen.reduce(0) { $0 + StopPriority.weight($1.priority) }
                    guard score >= bestScore else { continue }
                    var quickest: [TripStop]?
                    var quickestNeeds = Int.max
                    for order in Self.permutations(chosen) {
                        let n = needs(order)
                        if n < quickestNeeds {
                            quickestNeeds = n
                            quickest = order
                        }
                    }
                    guard let quickest, quickestNeeds <= available else { continue }
                    if score > bestScore || quickestNeeds < bestNeeds {
                        best = quickest
                        bestScore = score
                        bestNeeds = quickestNeeds
                    }
                }
            }
        }

        let chosenIDs = Set(best.map(\.id))
        let topPick = best.map(\.priority).max() ?? 0
        let skipped = pool.filter { !chosenIDs.contains($0.id) && $0.priority >= max(topPick, StopPriority.want) }
            .map { stop -> CatchUp.Skipped in
                let alone = needs([stop])
                return CatchUp.Skipped(stop: stop, needs: alone, tooLong: alone > available)
            }

        // Lay the plan out from a zero-length stop where you are now, then leave that stop off.
        var planTrip = trip
        planTrip.arrivedMinute = now
        planTrip.resumeMinute = nil
        planTrip.resumeStopID = nil
        var planned = [TripStop(id: "here", tripID: trip.id, title: "Here", coordinate: start, stayMinutes: 0, done: true)]
        planned += best.map { stop -> TripStop in
            var stop = stop
            stop.onDay = true
            stop.done = false
            return stop
        }
        if let next { planned.append(next) }
        let plan = Array(Self.lay(planned, trip: planTrip, planner: self).dropFirst())
        return CatchUp(now: now, next: next, deadline: deadline, available: available, picks: best, plan: plan,
                       spare: max(0, available - (best.isEmpty ? needs([]) : bestNeeds)), skipped: skipped,
                       lateForNext: next.map { now + travel(start, $0.coordinate) > deadline } ?? false)
    }

    /// The stops that change when you take a catch-up plan: picks go right after
    /// the finished stops, in order; other flexible stops before the next fixed
    /// one go back to the wish list. Returns the changed stops and the trip.
    public func applying(_ catchUp: CatchUp) -> (trip: Trip, stops: [TripStop]) {
        let day = dayStops
        let pickIDs = Set(catchUp.picks.map(\.id))
        let nextIndex = catchUp.next.flatMap { n in day.firstIndex { $0.id == n.id } } ?? day.count
        let done = day.filter(\.done)
        let before = day[..<nextIndex].filter { !$0.done && $0.isFixed }
        let after = day[nextIndex...].filter { !$0.done && !pickIDs.contains($0.id) }
        let picks = catchUp.picks.map { stop -> TripStop in
            var stop = stop
            stop.onDay = true
            return stop
        }
        var dropped = day[..<nextIndex].filter { !$0.done && !$0.isFixed && !pickIDs.contains($0.id) }
        var top = wishList.map(\.order).max() ?? 0
        for i in dropped.indices {
            top += 1
            dropped[i].onDay = false
            dropped[i].order = top
        }
        var newTrip = trip
        newTrip.resumeMinute = catchUp.now
        newTrip.resumeStopID = catchUp.picks.first?.id ?? catchUp.next?.id
        if newTrip.arrivedMinute == nil { newTrip.arrivedMinute = catchUp.now }
        return (newTrip, Self.renumbered(done + before + picks + after) + dropped)
    }

    static func combinations(of n: Int, choosing k: Int) -> [[Int]] {
        guard k > 0, k <= n else { return k == 0 ? [[]] : [] }
        var result: [[Int]] = []
        var current: [Int] = []
        func walk(_ from: Int) {
            if current.count == k { result.append(current); return }
            guard from < n else { return }
            for i in from..<n {
                current.append(i)
                walk(i + 1)
                current.removeLast()
            }
        }
        walk(0)
        return result
    }

    static func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        var result: [[T]] = []
        for (i, item) in items.enumerated() {
            var rest = items
            rest.remove(at: i)
            for tail in permutations(rest) { result.append([item] + tail) }
        }
        return result
    }
}

// MARK: - Example

public enum TripExample {
    /// A birthday in Chicago: a matinee, check-in and a dinner booking, with
    /// sights and shops around them.
    public static func make(on day: CalendarDay) -> (trip: Trip, stops: [TripStop]) {
        var trip = Trip(name: "Birthday in Chicago", day: day, startMinute: 600, endMinute: 1350)
        trip.isExample = true
        let id = trip.id
        func at(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }
        let day: [TripStop] = [
            TripStop(tripID: id, title: "Coffee and pastries", address: "Wabash Ave & Lake St", coordinate: at(41.8858, -87.6262),
                     kind: .meal, stayMinutes: 30),
            TripStop(tripID: id, title: "Art Institute", address: "111 S Michigan Ave", coordinate: at(41.8796, -87.6237),
                     kind: .sight, stayMinutes: 120, priority: StopPriority.top),
            TripStop(tripID: id, title: "Matinee", address: "24 W Randolph St", coordinate: at(41.8846, -87.6290),
                     kind: .show, stayMinutes: 150, fixedMinute: 840),
            TripStop(tripID: id, title: "Hotel check-in", address: "Michigan Ave & Ohio St", coordinate: at(41.8925, -87.6244),
                     kind: .stay, stayMinutes: 20, fixedMinute: 1020),
            TripStop(tripID: id, title: "Riverwalk stroll", address: "Chicago Riverwalk", coordinate: at(41.8879, -87.6260),
                     kind: .sight, stayMinutes: 40, priority: StopPriority.maybe),
            TripStop(tripID: id, title: "Birthday dinner", address: "W Hubbard St", coordinate: at(41.8899, -87.6300),
                     kind: .meal, stayMinutes: 105, fixedMinute: 1140),
        ]
        let wish: [TripStop] = [
            TripStop(tripID: id, title: "Architecture boat tour", address: "Michigan Ave Bridge", coordinate: at(41.8885, -87.6245),
                     kind: .sight, stayMinutes: 90, priority: StopPriority.top, onDay: false),
            TripStop(tripID: id, title: "Bookshop", address: "N Clark St", coordinate: at(41.8960, -87.6310),
                     kind: .shop, priority: StopPriority.want, onDay: false),
            TripStop(tripID: id, title: "Skydeck", address: "233 S Wacker Dr", coordinate: at(41.8789, -87.6359),
                     kind: .sight, stayMinutes: 75, priority: StopPriority.want, onDay: false),
        ]
        return (trip, TripPlanner.renumbered(day) + TripPlanner.renumbered(wish))
    }
}
