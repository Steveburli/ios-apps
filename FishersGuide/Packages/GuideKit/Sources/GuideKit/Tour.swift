import Foundation

/// What kind of place a stop is. Drives the map pin color and the category filters.
public enum StopCategory: String, Codable, CaseIterable, Sendable {
    case history, nature, arts, entertainment, landmark, area

    public var title: String {
        switch self {
        case .history: "History"
        case .nature: "Parks & Nature"
        case .arts: "Arts & Culture"
        case .entertainment: "Entertainment"
        case .landmark: "Landmarks"
        case .area: "Town Welcomes"
        }
    }
}

/// A range of compass headings, clockwise from `from` to `to` (both 0..<360).
/// `from: 300, to: 60` covers north-ish travel through 0.
public struct HeadingRange: Codable, Hashable, Sendable {
    public var from: Double
    public var to: Double

    public init(from: Double, to: Double) {
        self.from = from
        self.to = to
    }

    public func contains(_ heading: Double) -> Bool {
        let h = Geo.normalize(heading)
        let a = Geo.normalize(from), b = Geo.normalize(to)
        return a <= b ? (h >= a && h <= b) : (h >= a || h <= b)
    }
}

/// Narration that only fits one direction of travel, such as
/// "as you head north toward Noblesville …".
public struct DirectionalNarration: Codable, Hashable, Sendable {
    public var heading: HeadingRange
    public var text: String

    public init(heading: HeadingRange, text: String) {
        self.heading = heading
        self.text = text
    }
}

/// One place the guide talks about.
public struct Stop: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// A point of interest. It needs you to be heading toward it (or already inside
        /// its circle) and picks up a lead distance with speed.
        case poi
        /// A town or district welcome. It plays once when you're anywhere inside the circle,
        /// whatever your heading, and gives way to any point of interest.
        case area
    }

    public var id: String
    public var title: String
    public var subtitle: String
    public var category: StopCategory
    public var kind: Kind
    public var location: GeoPoint
    /// Meters. You're "at" the stop inside this circle.
    public var radius: Double
    /// Only trigger while traveling within one of these headings. Empty means any direction.
    public var approach: [HeadingRange]
    /// The main narration.
    public var narration: String
    /// Replaces `narration` when the heading matches (first match wins).
    public var directional: [DirectionalNarration]
    /// A one-line teaser for the "coming up" heads-up. Nil means no heads-up.
    public var teaser: String?
    /// The name of a recorded audio file in the app bundle (e.g. "conner-prairie.m4a").
    /// When present and found, it's played instead of the synthesized voice.
    public var audioFile: String?
    /// Higher wins when two stops trigger together.
    public var priority: Int
    /// For "Directions" and the detail screen.
    public var address: String?
    public var website: String?

    public init(id: String, title: String, subtitle: String, category: StopCategory, kind: Kind = .poi,
                location: GeoPoint, radius: Double, approach: [HeadingRange] = [], narration: String,
                directional: [DirectionalNarration] = [], teaser: String? = nil, audioFile: String? = nil,
                priority: Int = 0, address: String? = nil, website: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.kind = kind
        self.location = location
        self.radius = radius
        self.approach = approach
        self.narration = narration
        self.directional = directional
        self.teaser = teaser
        self.audioFile = audioFile
        self.priority = priority
        self.address = address
        self.website = website
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, category, kind, location, radius, approach, narration
        case directional, teaser, audioFile, priority, address, website
    }

    /// Optional fields may be left out of the JSON.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        category = try c.decode(StopCategory.self, forKey: .category)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .poi
        location = try c.decode(GeoPoint.self, forKey: .location)
        radius = try c.decode(Double.self, forKey: .radius)
        approach = try c.decodeIfPresent([HeadingRange].self, forKey: .approach) ?? []
        narration = try c.decode(String.self, forKey: .narration)
        directional = try c.decodeIfPresent([DirectionalNarration].self, forKey: .directional) ?? []
        teaser = try c.decodeIfPresent(String.self, forKey: .teaser)
        audioFile = try c.decodeIfPresent(String.self, forKey: .audioFile)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        address = try c.decodeIfPresent(String.self, forKey: .address)
        website = try c.decodeIfPresent(String.self, forKey: .website)
    }

    /// The narration for a direction of travel. Nil course means unknown (standing still).
    public func narration(forCourse course: Double?) -> String {
        if let course, let match = directional.first(where: { $0.heading.contains(course) }) {
            return match.text
        }
        return narration
    }
}

/// A whole guide: its stops plus a sample drive for the demo mode and screenshots.
public struct Tour: Codable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    /// Map framing: the center and span (degrees of latitude) to open on.
    public var center: GeoPoint
    public var span: Double
    public var stops: [Stop]
    /// Waypoints of a sample drive, in order.
    public var demoRoute: [GeoPoint]

    public init(id: String, title: String, summary: String, center: GeoPoint, span: Double,
                stops: [Stop], demoRoute: [GeoPoint]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.center = center
        self.span = span
        self.stops = stops
        self.demoRoute = demoRoute
    }

    public static func decode(_ data: Data) throws -> Tour {
        try JSONDecoder().decode(Tour.self, from: data)
    }

    /// The bundled Fishers & Hamilton County guide.
    public static func bundledFishers() throws -> Tour {
        guard let url = Bundle.module.url(forResource: "FishersTour", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    public func stop(id: String) -> Stop? {
        stops.first { $0.id == id }
    }
}
