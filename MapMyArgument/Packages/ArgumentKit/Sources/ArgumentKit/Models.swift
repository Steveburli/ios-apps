import Foundation

// The argument map, in the same JSON shape as the website (web/js/engine.js `normalize`),
// so share codes work in both directions. Decoding is forgiving: missing fields get
// defaults, numbers are clamped, unknown kinds and perspectives are dropped or replaced.

public enum SourceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case study, government, news, expert, reference, advocacy, social, personal

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .study: return "Peer-reviewed study"
        case .government: return "Government data"
        case .news: return "News report"
        case .expert: return "Expert or book"
        case .reference: return "Encyclopedia or reference"
        case .advocacy: return "Advocacy group"
        case .social: return "Social media post"
        case .personal: return "Personal experience"
        }
    }
}

public enum Lean: String, Codable, CaseIterable, Sendable, Identifiable {
    case neutral, left, right

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .neutral: return "Seen as neutral"
        case .left: return "Seen as left-leaning"
        case .right: return "Seen as right-leaning"
        }
    }
}

public enum Trust: String, Codable, CaseIterable, Sendable {
    case trust, unfamiliar, distrust

    public var label: String {
        switch self {
        case .trust: return "Trust"
        case .unfamiliar: return "Not sure"
        case .distrust: return "Don't trust"
        }
    }
}

public enum Stance: String, Codable, CaseIterable, Sendable {
    case `for`, against, unsure

    public var label: String {
        switch self {
        case .for: return "For"
        case .against: return "Against"
        case .unsure: return "Not sure yet"
        }
    }
}

public enum Familiarity {
    public static let labels = [
        "I have no idea what that is",
        "I've heard of it",
        "I know the basics",
        "I've read up on it",
        "I've researched it thoroughly",
    ]

    public static func label(_ value: Int) -> String {
        labels[max(1, min(5, value)) - 1]
    }
}

public enum Importance {
    public static let labels = ["A little", "Somewhat", "A fair bit", "A lot", "Everything"]

    public static func label(_ value: Int) -> String {
        labels[max(1, min(5, value)) - 1]
    }
}

public struct Source: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var kind: SourceKind
    public var lean: Lean

    public init(id: String = Ids.make("s"), title: String = "", url: String = "", kind: SourceKind = .news, lean: Lean = .neutral) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
        self.lean = lean
    }

    enum CodingKeys: String, CodingKey { case id, title, url, kind, lean }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? Ids.make("s")
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        kind = ((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil).flatMap(SourceKind.init(rawValue:)) ?? .news
        lean = ((try? c.decodeIfPresent(String.self, forKey: .lean)) ?? nil).flatMap(Lean.init(rawValue:)) ?? .neutral
    }
}

public struct Counter: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var strength: Int
    public var answered: Bool

    public init(id: String = Ids.make("x"), text: String = "", strength: Int = 3, answered: Bool = false) {
        self.id = id
        self.text = text
        self.strength = strength
        self.answered = answered
    }

    enum CodingKeys: String, CodingKey { case id, text, strength, answered }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? Ids.make("x")
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        strength = Lenient.int(c, .strength, default: 3, 1, 5)
        answered = (try? c.decodeIfPresent(Bool.self, forKey: .answered)) ?? false
    }
}

public struct Claim: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// The claim this one holds up, or nil for a top-level reason (a pillar).
    public var parent: String?
    public var text: String
    /// How much the claim above depends on this one, 1–5.
    public var importance: Int
    /// How sure the author is that it's true, 0–100.
    public var confidence: Int
    /// How much the author has looked into it, 1–5.
    public var familiarity: Int
    /// Held up by belief alone.
    public var cloud: Bool
    /// People who agree.
    public var votes: Int
    public var sources: [Source]
    public var counters: [Counter]
    /// Perspective ids that would reject this outright.
    public var disputedBy: [String]

    public init(id: String = Ids.make("c"), parent: String? = nil, text: String = "", importance: Int = 3,
                confidence: Int = 60, familiarity: Int = 3, cloud: Bool = false, votes: Int = 0,
                sources: [Source] = [], counters: [Counter] = [], disputedBy: [String] = []) {
        self.id = id
        self.parent = parent
        self.text = text
        self.importance = importance
        self.confidence = confidence
        self.familiarity = familiarity
        self.cloud = cloud
        self.votes = votes
        self.sources = sources
        self.counters = counters
        self.disputedBy = disputedBy
    }

    enum CodingKeys: String, CodingKey {
        case id, parent, text, importance, confidence, familiarity, cloud, votes, sources, counters, disputedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? Ids.make("c")
        let p = (try? c.decodeIfPresent(String.self, forKey: .parent)) ?? nil
        parent = (p?.isEmpty ?? true) ? nil : p
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        importance = Lenient.int(c, .importance, default: 3, 1, 5)
        confidence = Lenient.int(c, .confidence, default: 50, 0, 100)
        familiarity = Lenient.int(c, .familiarity, default: 3, 1, 5)
        cloud = (try? c.decodeIfPresent(Bool.self, forKey: .cloud)) ?? false
        votes = Lenient.int(c, .votes, default: 0, 0, 1_000_000)
        sources = (try? c.decodeIfPresent([Source].self, forKey: .sources)) ?? []
        counters = (try? c.decodeIfPresent([Counter].self, forKey: .counters)) ?? []
        let disputed = (try? c.decodeIfPresent([String].self, forKey: .disputedBy)) ?? []
        disputedBy = disputed.filter { id in Perspective.all.contains { $0.id == id } }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        if let parent { try c.encode(parent, forKey: .parent) } else { try c.encodeNil(forKey: .parent) }
        try c.encode(text, forKey: .text)
        try c.encode(importance, forKey: .importance)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(familiarity, forKey: .familiarity)
        try c.encode(cloud, forKey: .cloud)
        try c.encode(votes, forKey: .votes)
        try c.encode(sources, forKey: .sources)
        try c.encode(counters, forKey: .counters)
        try c.encode(disputedBy, forKey: .disputedBy)
    }
}

public struct ArgumentMap: Codable, Hashable, Identifiable, Sendable {
    public var version: Int = 1
    public var id: String
    public var topic: String
    /// The author's position: the roof of the tower.
    public var thesis: String
    public var stance: Stance
    public var author: String
    /// When this map is someone's rating of another map, that map's id.
    public var basedOn: String
    /// Ratings whose agreement has already been counted as votes.
    public var counted: [String]
    /// How much the author trusts each kind of source. Missing means "not sure".
    public var trust: [String: Trust]
    public var created: String
    public var updated: String
    public var claims: [Claim]

    public init(id: String = Ids.make("map"), topic: String = "", thesis: String = "", stance: Stance = .for,
                author: String = "", basedOn: String = "", counted: [String] = [], trust: [String: Trust] = [:],
                created: String = Ids.now(), updated: String = Ids.now(), claims: [Claim] = []) {
        self.id = id
        self.topic = topic
        self.thesis = thesis
        self.stance = stance
        self.author = author
        self.basedOn = basedOn
        self.counted = counted
        self.trust = trust
        self.created = created
        self.updated = updated
        self.claims = claims
    }

    public func trust(_ kind: SourceKind) -> Trust {
        trust[kind.rawValue] ?? .unfamiliar
    }

    enum CodingKeys: String, CodingKey {
        case version, id, topic, thesis, stance, author, basedOn, counted, trust, created, updated, claims
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        version = 1
        let rawID = string(.id)
        id = rawID.isEmpty ? Ids.make("map") : rawID
        topic = string(.topic)
        thesis = string(.thesis)
        stance = Stance(rawValue: string(.stance)) ?? .unsure
        author = string(.author)
        basedOn = string(.basedOn)
        counted = (try? c.decodeIfPresent([String].self, forKey: .counted)) ?? []
        let rawTrust = (try? c.decodeIfPresent([String: String].self, forKey: .trust)) ?? [:]
        var trust: [String: Trust] = [:]
        for kind in SourceKind.allCases {
            if let value = rawTrust[kind.rawValue].flatMap(Trust.init(rawValue:)) { trust[kind.rawValue] = value }
        }
        self.trust = trust
        created = string(.created)
        updated = string(.updated)
        claims = (try? c.decodeIfPresent([Claim].self, forKey: .claims)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(id, forKey: .id)
        try c.encode(topic, forKey: .topic)
        try c.encode(thesis, forKey: .thesis)
        try c.encode(stance, forKey: .stance)
        try c.encode(author, forKey: .author)
        try c.encode(basedOn, forKey: .basedOn)
        try c.encode(counted, forKey: .counted)
        try c.encode(trust.mapValues(\.rawValue), forKey: .trust)
        try c.encode(created, forKey: .created)
        try c.encode(updated, forKey: .updated)
        try c.encode(claims, forKey: .claims)
    }

    // MARK: Structure

    /// Top-level claims: no parent, a parent that no longer exists, or themselves as parent.
    public var roots: [Claim] {
        let ids = Set(claims.map(\.id))
        return claims.filter { claim in
            guard let parent = claim.parent, parent != claim.id, ids.contains(parent) else { return true }
            return false
        }
    }

    public func children(of id: String) -> [Claim] {
        claims.filter { $0.parent == id && $0.id != id }
    }

    /// Claims in reading order (each reason, then the points under it) with their labels: 1, 1a, 1b, 2…
    public var outline: [OutlineItem] {
        var out: [OutlineItem] = []
        var seen = Set<String>()
        func walk(_ claim: Claim, _ depth: Int, _ label: String) {
            guard seen.insert(claim.id).inserted else { return }
            out.append(OutlineItem(claim: claim, depth: depth, label: label))
            for (i, kid) in children(of: claim.id).enumerated() {
                walk(kid, depth + 1, label + Self.letter(i))
            }
        }
        for (i, root) in roots.enumerated() { walk(root, 0, String(i + 1)) }
        return out
    }

    /// a, b, c… for the points under a claim.
    public static func letter(_ i: Int) -> String {
        String(Character(Unicode.Scalar(UInt8(97 + min(max(i, 0), 25)))))
    }

    public var labels: [String: String] {
        Dictionary(outline.map { ($0.claim.id, $0.label) }, uniquingKeysWith: { a, _ in a })
    }

    public func depth(of claim: Claim) -> Int {
        var depth = 0
        var current = claim
        var seen: Set<String> = [claim.id]
        while let parent = current.parent, let next = claims.first(where: { $0.id == parent }), seen.insert(next.id).inserted {
            depth += 1
            current = next
        }
        return depth
    }

    /// Removes a claim and everything under it.
    public mutating func removeClaim(_ id: String) {
        var doomed: Set<String> = [id]
        var grew = true
        while grew {
            grew = false
            for claim in claims where !doomed.contains(claim.id) {
                if let parent = claim.parent, doomed.contains(parent) {
                    doomed.insert(claim.id)
                    grew = true
                }
            }
        }
        claims.removeAll { doomed.contains($0.id) }
    }

    public func index(of id: String) -> Int? {
        claims.firstIndex { $0.id == id }
    }
}

/// One line of a map's outline.
public struct OutlineItem: Identifiable, Sendable {
    public let claim: Claim
    public let depth: Int
    public let label: String
    public var id: String { claim.id }
}

// MARK: - Helpers

public enum Ids {
    public static func make(_ prefix: String) -> String {
        let random = String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))
        return prefix + "-" + random
    }

    public static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

enum Lenient {
    /// Reads a number that might be an Int, a Double or missing, rounds and clamps it.
    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K, default fallback: Int, _ lo: Int, _ hi: Int) -> Int {
        let value: Double?
        if let i = (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil {
            value = Double(i)
        } else if let d = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil, d.isFinite {
            value = d
        } else {
            value = nil
        }
        guard let value else { return fallback }
        return Int(min(Double(hi), max(Double(lo), value)).rounded())
    }
}
