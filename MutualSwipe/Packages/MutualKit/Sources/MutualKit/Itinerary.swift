import Foundation

/// A planned outing on one card, like "Dinner and a movie in Broad Ripple":
/// a few stops in order, each with a time and a place, plus photos people
/// swipe through on the card. Saved with the card as one JSON string, so a
/// plan syncs like any other card text.
public struct Itinerary: Codable, Equatable, Sendable {
    public var stops: [Stop]
    /// Photos in the order they're swiped. Each is a `PhotoRef` string: an
    /// https link, `starter:<id>` for a bundled photo, or `photo:<file>` for
    /// one added from a phone (synced as a CloudKit asset).
    public var photos: [String]
    /// Where to look for the places, like "Broad Ripple, Indianapolis".
    public var area: String

    public init(stops: [Stop] = [], photos: [String] = [], area: String = "") {
        self.stops = stops
        self.photos = photos
        self.area = area
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stops = try c.decodeIfPresent([Stop].self, forKey: .stops) ?? []
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        area = try c.decodeIfPresent(String.self, forKey: .area) ?? ""
    }

    public static let maxStops = 8
    public static let maxPhotos = 10

    /// One place on the plan.
    public struct Stop: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        /// As people write it: "4:00 PM". Empty when there's no set time.
        public var time: String
        /// What you do there: "Drinks", "Movie".
        public var what: String
        /// The place's name.
        public var place: String
        public var address: String
        public var note: String
        /// The place's own website, or empty.
        public var website: String
        public var latitude: Double?
        public var longitude: Double?

        public init(id: String = makeID(), time: String = "", what: String = "", place: String = "", address: String = "",
                    note: String = "", website: String = "", latitude: Double? = nil, longitude: Double? = nil) {
            self.id = id
            self.time = time
            self.what = what
            self.place = place
            self.address = address
            self.note = note
            self.website = website
            self.latitude = latitude
            self.longitude = longitude
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? makeID()
            time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
            what = try c.decodeIfPresent(String.self, forKey: .what) ?? ""
            place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
            address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            website = try c.decodeIfPresent(String.self, forKey: .website) ?? ""
            latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
            longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        }

        /// Minutes after midnight, when the time can be read.
        public var minutes: Int? { Itinerary.minutes(of: time) }

        public var hasLocation: Bool { latitude != nil && longitude != nil }

        /// "Drinks at Thunderbird", or whichever half there is.
        public var headline: String {
            switch (what.isEmpty, place.isEmpty) {
            case (false, false): return "\(what) at \(place)"
            case (true, false): return place
            case (false, true): return what
            case (true, true): return "Stop"
            }
        }

        /// What to search a map for.
        public func searchText(area: String) -> String {
            let name = place.isEmpty ? what : place
            let near = address.isEmpty ? area : address
            return [name, near].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    // MARK: JSON

    /// The plan as the JSON string saved with the card.
    public func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func decode(_ text: String?) -> Itinerary? {
        guard let text, !text.isEmpty else { return nil }
        return try? JSONDecoder().decode(Itinerary.self, from: Data(text.utf8))
    }

    // MARK: Cleaning

    /// Trims and limits every field, keeps only safe links and photo
    /// references, and drops empty stops. Cleaning twice changes nothing.
    public func cleaned() -> Itinerary {
        func limit(_ text: String, _ count: Int) -> String {
            String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(count))
        }
        let stops = stops.compactMap { stop -> Stop? in
            var stop = stop
            stop.time = limit(stop.time, 20)
            stop.what = limit(stop.what, 60)
            stop.place = limit(stop.place, 100)
            stop.address = limit(stop.address, 160)
            stop.note = limit(stop.note, 300)
            stop.website = CardText.safeURL(stop.website)
            if stop.latitude == nil || stop.longitude == nil {
                stop.latitude = nil
                stop.longitude = nil
            }
            if stop.what.isEmpty && stop.place.isEmpty { return nil }
            return stop
        }
        var seen = Set<String>()
        let photos = photos.compactMap { raw -> String? in
            guard let ref = PhotoRef(raw) else { return nil }
            let text = ref.string
            return seen.insert(text).inserted ? text : nil
        }
        return Itinerary(stops: Array(stops.prefix(Self.maxStops)), photos: Array(photos.prefix(Self.maxPhotos)),
                         area: limit(area, 80))
    }

    // MARK: Text for other places

    /// One line per stop, for card details, calendar notes and sharing.
    public var summary: String {
        stops.map { stop in
            var line = stop.time.isEmpty ? stop.headline : "\(stop.time) · \(stop.headline)"
            if !stop.address.isEmpty { line += " (\(stop.address))" }
            return line
        }.joined(separator: "\n")
    }

    /// "3 stops · 4:00 PM to 8:00 PM".
    public var span: String {
        let count = "\(stops.count) \(stops.count == 1 ? "stop" : "stops")"
        let times = stops.map(\.time).filter { !$0.isEmpty }
        guard let first = times.first else { return count }
        guard let last = times.last, times.count > 1 else { return "\(count) · from \(first)" }
        return "\(count) · \(first) to \(last)"
    }

    // MARK: Times

    /// Minutes after midnight for "4 pm", "4:30 PM", "16:00", "noon" or "midnight".
    public static func minutes(of time: String) -> Int? {
        let text = time.trimmingCharacters(in: .whitespaces).lowercased()
        if text == "noon" { return 12 * 60 }
        if text == "midnight" { return 0 }
        let pattern = "^(\\d{1,2})(?::([0-5]\\d))?\\s*(?:([ap])\\.?\\s*m\\.?)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let range = Range(match.range(at: i), in: text) else { return nil }
            return String(text[range])
        }
        guard let hour = group(1).flatMap(Int.init) else { return nil }
        let minute = group(2).flatMap(Int.init) ?? 0
        switch group(3) {
        case "a"?:
            guard (1...12).contains(hour) else { return nil }
            return (hour % 12) * 60 + minute
        case "p"?:
            guard (1...12).contains(hour) else { return nil }
            return (hour % 12 + 12) * 60 + minute
        default:
            guard hour < 24 else { return nil }
            return hour * 60 + minute
        }
    }

    /// "4:00 PM" for 960.
    public static func format(minutes: Int) -> String {
        let total = ((minutes % 1440) + 1440) % 1440
        let hour = total / 60
        let minute = total % 60
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", twelve, minute, hour < 12 ? "AM" : "PM")
    }
}

/// Where one of a plan's photos comes from.
public enum PhotoRef: Equatable, Sendable {
    /// A photo on the web, usually from the place's own website.
    case web(URL)
    /// A photo bundled with Mutual's ready-made decks, by starter card ID.
    case starter(String)
    /// A photo someone added from their phone, by file name.
    case phone(String)

    public init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("starter:") {
            let id = String(text.dropFirst(8))
            guard !id.isEmpty else { return nil }
            self = .starter(id)
        } else if text.hasPrefix("photo:") {
            let name = String(text.dropFirst(6))
            // A plain file name only: nothing that could walk out of the photos folder.
            guard !name.isEmpty, name.range(of: "^[A-Za-z0-9_-]+\\.jpg$", options: .regularExpression) != nil else { return nil }
            self = .phone(name)
        } else {
            let safe = CardText.safeURL(text)
            guard safe.hasPrefix("https://"), let url = URL(string: safe) else { return nil }
            self = .web(url)
        }
    }

    public var string: String {
        switch self {
        case .web(let url): return url.absoluteString
        case .starter(let id): return "starter:" + id
        case .phone(let name): return "photo:" + name
        }
    }
}
