import Foundation

/// Lines up two maps of the same topic, the same way as `compare` in web/js/engine.js.
/// Claims match by id first (a friend who rated your map keeps your ids), then by wording.
/// The discussion queue starts at the foundations: there's no point arguing whether X is
/// good until you agree X exists.
public enum Compare {
    public enum Kind: String, Sendable {
        /// Both think it's true, within 30 points of each other.
        case agree
        /// Both think it's true, but 30 or more points apart.
        case degree
        /// Neither thinks it's true.
        case bothDoubt
        /// One thinks it's true, the other doesn't.
        case disagree

        var order: Int {
            switch self {
            case .disagree: return 0
            case .degree: return 1
            case .bothDoubt: return 2
            case .agree: return 3
            }
        }
    }

    public struct Conflict: Sendable, Equatable {
        public enum Side: String, Sendable { case mine, theirs }
        public let side: Side
        public let source: String
        public let kind: SourceKind
    }

    public struct Item: Sendable, Identifiable {
        public var id: String { mine }
        public let mine: String
        public let theirs: String
        public let text: String
        public let theirText: String
        public let match: Double
        public let myConfidence: Int
        public let theirConfidence: Int
        public let kind: Kind
        public let conflicts: [Conflict]
        public let depth: Int
        public let importance: Int
    }

    public struct TrustSplit: Sendable, Equatable {
        public let kind: SourceKind
        public let mine: Trust
        public let theirs: Trust
    }

    public struct Result: Sendable {
        public let sameStance: Bool
        public let items: [Item]
        public let queue: [Item]
        public let onlyMine: [String]
        public let onlyTheirs: [String]
        public let trustSplit: [TrustSplit]
        public let agreeCount: Int
        public let disagreeCount: Int
        public let degreeCount: Int
    }

    static let stopWords: Set<String> = Set((
        "the a an and or but of to in on for is are was were be been it its this that these those " +
        "with as at by from than then so if not no do does did can will would should could have has had i you we they " +
        "he she them our your their my me us more most less very").split(separator: " ").map(String.init))

    static func words(_ text: String) -> Set<String> {
        let cleaned = String(text.lowercased().map { ch -> Character in
            if ch.isWhitespace { return " " }
            if let a = ch.asciiValue, (a >= 97 && a <= 122) || (a >= 48 && a <= 57) { return ch }
            return " "
        })
        return Set(cleaned.split(separator: " ").map(String.init).filter { $0.count > 2 && !stopWords.contains($0) })
    }

    /// Word overlap (Jaccard) after dropping short and common words.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let A = words(a), B = words(b)
        guard !A.isEmpty, !B.isEmpty else { return 0 }
        let both = A.intersection(B).count
        return Double(both) / Double(A.count + B.count - both)
    }

    static func depths(_ map: ArgumentMap) -> [String: Int] {
        var depth: [String: Int] = [:]
        for root in map.roots {
            var seen = Set<String>()
            func walk(_ c: Claim, _ d: Int) {
                guard seen.insert(c.id).inserted else { return }
                depth[c.id] = d
                for kid in map.children(of: c.id) { walk(kid, d + 1) }
            }
            walk(root, 0)
        }
        return depth
    }

    public static func run(_ mine: ArgumentMap, _ theirs: ArgumentMap) -> Result {
        var pairs: [(Claim, Claim, Double)] = []
        var usedTheirs = Set<String>()
        let theirByID = Dictionary(theirs.claims.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var unmatched: [Claim] = []
        for c in mine.claims {
            if let t = theirByID[c.id] {
                pairs.append((c, t, 1))
                usedTheirs.insert(t.id)
            } else {
                unmatched.append(c)
            }
        }
        var candidates: [(Claim, Claim, Double, Int)] = []
        for c in unmatched {
            for t in theirs.claims where !usedTheirs.contains(t.id) {
                let s = similarity(c.text, t.text)
                if s >= 0.5 { candidates.append((c, t, s, candidates.count)) }
            }
        }
        candidates.sort { $0.2 != $1.2 ? $0.2 > $1.2 : $0.3 < $1.3 }
        var usedMine = Set(pairs.map { $0.0.id })
        for (c, t, s, _) in candidates where !usedMine.contains(c.id) && !usedTheirs.contains(t.id) {
            pairs.append((c, t, s))
            usedMine.insert(c.id)
            usedTheirs.insert(t.id)
        }

        let myDepth = depths(mine)
        let items: [Item] = pairs.map { c, t, s in
            let a = c.confidence, b = t.confidence
            let kind: Kind
            if a >= 50 && b >= 50 { kind = abs(a - b) >= 30 ? .degree : .agree }
            else if a < 50 && b < 50 { kind = .bothDoubt }
            else { kind = .disagree }
            var conflicts: [Conflict] = []
            for src in c.sources where theirs.trust(src.kind) == .distrust {
                conflicts.append(Conflict(side: .mine, source: src.id, kind: src.kind))
            }
            for src in t.sources where mine.trust(src.kind) == .distrust {
                conflicts.append(Conflict(side: .theirs, source: src.id, kind: src.kind))
            }
            return Item(mine: c.id, theirs: t.id, text: c.text, theirText: t.text, match: s,
                        myConfidence: a, theirConfidence: b, kind: kind, conflicts: conflicts,
                        depth: myDepth[c.id] ?? 0, importance: c.importance)
        }

        let onlyMine = mine.claims.filter { !usedMine.contains($0.id) }.map(\.id)
        let onlyTheirs = theirs.claims.filter { !usedTheirs.contains($0.id) }.map(\.id)

        let queue = items.enumerated()
            .filter { $0.element.kind == .disagree || $0.element.kind == .degree || !$0.element.conflicts.isEmpty }
            .sorted { x, y in
                let a = x.element, b = y.element
                if a.depth != b.depth { return a.depth > b.depth }
                if a.kind.order != b.kind.order { return a.kind.order < b.kind.order }
                if a.importance != b.importance { return a.importance > b.importance }
                return x.offset < y.offset
            }
            .map(\.element)

        let split = SourceKind.allCases
            .filter { mine.trust($0) != theirs.trust($0) }
            .map { TrustSplit(kind: $0, mine: mine.trust($0), theirs: theirs.trust($0)) }

        return Result(
            sameStance: mine.stance == theirs.stance,
            items: items, queue: queue, onlyMine: onlyMine, onlyTheirs: onlyTheirs, trustSplit: split,
            agreeCount: items.filter { $0.kind == .agree || $0.kind == .bothDoubt }.count,
            disagreeCount: items.filter { $0.kind == .disagree }.count,
            degreeCount: items.filter { $0.kind == .degree }.count)
    }
}

/// A map as one line of text: "MMA1." and the map's JSON in URL-safe base64. Same format as the website.
public enum ShareCode {
    public static let prefix = "MMA1."

    public enum Failure: LocalizedError {
        case notACode, empty, damaged

        public var errorDescription: String? {
            switch self {
            case .notACode: return "That isn't a Map My Argument code. Codes start with MMA1."
            case .empty: return "The code is empty."
            case .damaged: return "The code is damaged. Copy the whole thing and try again."
            }
        }
    }

    public static func encode(_ map: ArgumentMap) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(map)) ?? Data()
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return prefix + b64
    }

    /// Finds a code anywhere in the text (a message can have words around it) and reads it.
    public static func decode(_ text: String) throws -> ArgumentMap {
        guard let range = text.range(of: prefix) else { throw Failure.notACode }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let body = String(text[range.upperBound...].prefix { allowed.contains($0) })
        guard !body.isEmpty else { throw Failure.empty }
        var b64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let map = try? JSONDecoder().decode(ArgumentMap.self, from: data) else {
            throw Failure.damaged
        }
        return map
    }
}
