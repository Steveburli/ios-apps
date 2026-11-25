import Foundation

// The scoring engine, the same rules as web/js/engine.js. The shared cases in
// Tests/ArgumentKitTests/Fixtures/engine-cases.json (made from the JavaScript engine by
// tools/make-fixtures.mjs) keep the two in step. ENGINE.md explains every number.

public struct Perspective: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let blurb: String
    public let distrustLeans: [Lean]
    public let distrustKinds: [SourceKind]
    public let removeClouds: Bool
    public let singleSourceCountsZero: Bool

    public static let all: [Perspective] = [
        Perspective(id: "progressive", label: "Progressive",
                    blurb: "Throws out right-leaning sources, then rejects the premises you said a progressive would.",
                    distrustLeans: [.right], distrustKinds: [], removeClouds: false, singleSourceCountsZero: false),
        Perspective(id: "conservative", label: "Conservative",
                    blurb: "Throws out left-leaning sources, then rejects the premises you said a conservative would.",
                    distrustLeans: [.left], distrustKinds: [], removeClouds: false, singleSourceCountsZero: false),
        Perspective(id: "libertarian", label: "Libertarian",
                    blurb: "Doesn't take government data on faith, then rejects the premises you said a libertarian would.",
                    distrustLeans: [], distrustKinds: [.government], removeClouds: false, singleSourceCountsZero: false),
        Perspective(id: "scientist", label: "Scientist",
                    blurb: "Ignores anecdotes, social posts and advocacy groups, and blows away every belief cloud.",
                    distrustLeans: [], distrustKinds: [.social, .personal, .advocacy], removeClouds: true, singleSourceCountsZero: false),
        Perspective(id: "skeptic", label: "Skeptic",
                    blurb: "Won't accept anything that rests on a single source, and ignores social posts.",
                    distrustLeans: [], distrustKinds: [.social], removeClouds: false, singleSourceCountsZero: true),
    ]

    public static func find(_ id: String) -> Perspective? {
        all.first { $0.id == id }
    }
}

/// The numbers. See ENGINE.md.
public enum K {
    public static func trustWeight(_ t: Trust) -> Double {
        switch t {
        case .trust: return 1
        case .unfamiliar: return 0.7
        case .distrust: return 0
        }
    }
    public static let tierValue: [Double] = [0, 0.45, 0.75, 1]
    public static let cloudSupport = 0.35
    public static let childShare = 0.5
    public static let voteStep = 0.05, voteCap = 0.15
    public static let counterUnanswered = 0.05, counterAnswered = 0.01
    public static let confidenceFloor = 0.6
    public static let termiteFactor = 0.7
    public static let termiteConfidence = 70, termiteFamiliarity = 2
    public static let humbleConfidence = 35, humbleFamiliarity = 4
    public static let demandBase = 0.2, demandStep = 0.14
    public static let fallThreshold = 0.35
    public static let quakeShake = 0.8
    public static let lowConviction = 50, convictionPressure = 0.75
    public static let leanScale = 24.0, leanMax = 20.0, singleLean = 12.0
}

public enum ClaimStatus: String, Sendable {
    case solid, strained, sagging, failing, fallen

    public var label: String {
        switch self {
        case .solid: return "Solid"
        case .strained: return "Strained"
        case .sagging: return "Sagging"
        case .failing: return "Failing"
        case .fallen: return "Fell"
        }
    }

    static func from(stability: Double) -> ClaimStatus {
        if stability >= 1 { return .solid }
        if stability >= 0.6 { return .strained }
        if stability >= K.fallThreshold { return .sagging }
        return .failing
    }
}

public struct Grade: Sendable, Equatable {
    public let id: String
    public let label: String
    public let line: String

    static let empty = Grade(id: "empty", label: "Empty lot", line: "Add a reason to start building.")

    static func from(score: Double) -> Grade {
        if score >= 0.85 { return Grade(id: "fortress", label: "Fortress", line: "Broad foundations. This one can take a hit.") }
        if score >= 0.65 { return Grade(id: "solid", label: "Solid", line: "It stands, with a few soft spots worth shoring up.") }
        if score >= 0.45 { return Grade(id: "leaning", label: "Leaning", line: "It's standing, but it leans toward its weakest pillars.") }
        if score >= 0.25 { return Grade(id: "sagging", label: "Sagging", line: "The roof is heavier than the foundations can carry.") }
        return Grade(id: "toppled", label: "Toppled", line: "The weight of the claims is too much for the support under them.")
    }
}

public struct ClaimResult: Sendable, Equatable {
    public let id: String
    public let depth: Int
    public let importance: Int
    public let strength: Double
    public let stability: Double
    public let status: ClaimStatus
    /// "", "I", "II" or "IXI"
    public let tier: String
    public let sourceCount: Int
    public let droppedSources: [String]
    public let cloud: Bool
    public let termites: Bool
    public let humble: Bool
    public let unsupported: Bool
    public let unansweredCounters: Int
    public let fallen: Bool
    public let children: [String]
}

public struct Flags: Sendable, Equatable {
    public var termites: [String] = []
    public var humble: [String] = []
    public var unsupported: [String] = []
    public var headInClouds = false
    public var clouds = 0
    public var cherryPicking = false
    public var unansweredCounters = 0
}

public struct Evaluation: Sendable {
    public let claims: [String: ClaimResult]
    public let score: Double
    public let grade: Grade
    /// Degrees; positive leans right.
    public let lean: Double
    public let weight: Int
    public let toppled: Bool
    public let flags: Flags
}

/// How the world is changed before scoring: by a stress test or an opponent.
public struct Conditions: Sendable {
    public var distrustKinds: [SourceKind] = []
    public var distrustLeans: [Lean] = []
    public var singleSourceCountsZero = false
    public var removeClouds = false
    public var removed: Set<String> = []
    public var shake: Double?
    public var collapseTermites = false
    public var lowConvictionPressure: Double?
    /// Claims under the fall threshold fall, and hold nothing up.
    public var fall = false

    public init() {}
}

public enum Engine {
    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
    static func clampInt(_ x: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, x)) }

    public static func demand(_ importance: Int) -> Double {
        K.demandBase + K.demandStep * Double(clampInt(importance, 1, 5))
    }

    public static func hasTermites(_ c: Claim) -> Bool {
        c.confidence >= K.termiteConfidence && c.familiarity <= K.termiteFamiliarity
    }

    public static func isHumble(_ c: Claim) -> Bool {
        c.confidence <= K.humbleConfidence && c.familiarity >= K.humbleFamiliarity
    }

    static func normTitle(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func tierLabel(_ n: Int) -> String {
        ["", "I", "II", "IXI"][min(3, n)]
    }

    struct SourceSupport {
        let value: Double
        let count: Int
        let tier: String
        let dropped: [String]
    }

    static func sourceSupport(_ map: ArgumentMap, _ claim: Claim, _ cond: Conditions) -> SourceSupport {
        var seen = Set<String>()
        var weights: [Double] = []
        var dropped: [String] = []
        for s in claim.sources {
            let title = normTitle(s.title)
            let key = title.isEmpty ? s.id : title
            guard seen.insert(key).inserted else { continue }
            var w = K.trustWeight(map.trust(s.kind))
            if cond.distrustKinds.contains(s.kind) { w = 0 }
            if cond.distrustLeans.contains(s.lean) { w = 0 }
            if w > 0 { weights.append(w) } else { dropped.append(s.id) }
        }
        weights.sort(by: >)
        let counted = Array(weights.prefix(3))
        var n = counted.count
        if cond.singleSourceCountsZero && n == 1 { n = 0 }
        let avg = counted.isEmpty ? 0 : counted.reduce(0, +) / Double(counted.count)
        return SourceSupport(value: n > 0 ? K.tierValue[n] * avg : 0, count: n, tier: tierLabel(n), dropped: dropped)
    }

    static func counterLoad(_ c: Claim) -> Double {
        c.counters.reduce(0) { load, k in
            load + Double(clampInt(k.strength, 1, 5)) * (k.answered ? K.counterAnswered : K.counterUnanswered)
        }
    }

    static func voteBonus(_ votes: Int) -> Double {
        votes <= 0 ? 0 : min(K.voteCap, K.voteStep * log2(1 + Double(votes)))
    }

    // MARK: Evaluate

    public static func evaluate(_ map: ArgumentMap, _ cond: Conditions = Conditions()) -> Evaluation {
        var results: [String: ClaimResult] = [:]

        func visit(_ claim: Claim, _ depth: Int, _ ancestors: Set<String>) -> ClaimResult? {
            if ancestors.contains(claim.id) { return nil }
            var path = ancestors
            path.insert(claim.id)
            let children = map.children(of: claim.id).compactMap { visit($0, depth + 1, path) }

            let src = sourceSupport(map, claim, cond)
            let cloud = claim.cloud && !cond.removeClouds ? K.cloudSupport : 0
            var fromChildren = 0.0
            for r in children where !r.fallen {
                fromChildren += r.strength * (Double(clampInt(r.importance, 1, 5)) / 5) * K.childShare
            }
            let raw = src.value + cloud + fromChildren + voteBonus(claim.votes) - counterLoad(claim)
            let confidence = Double(clampInt(claim.confidence, 0, 100))
            let termites = hasTermites(claim)
            var strength = clamp(raw, 0, 1) * (K.confidenceFloor + (1 - K.confidenceFloor) * confidence / 100)
            if termites { strength *= K.termiteFactor }
            if let shake = cond.shake { strength *= shake }
            if let pressure = cond.lowConvictionPressure, confidence < Double(K.lowConviction) { strength *= pressure }

            let importance = clampInt(claim.importance, 1, 5)
            let stability = strength / demand(importance)
            var fallen = cond.removed.contains(claim.id)
            if cond.collapseTermites && termites { fallen = true }
            if cond.fall && stability < K.fallThreshold { fallen = true }

            let r = ClaimResult(
                id: claim.id, depth: depth, importance: importance,
                strength: fallen ? 0 : strength, stability: fallen ? 0 : stability,
                status: fallen ? .fallen : ClaimStatus.from(stability: stability),
                tier: src.tier, sourceCount: src.count, droppedSources: src.dropped,
                cloud: claim.cloud && !cond.removeClouds,
                termites: termites, humble: isHumble(claim),
                unsupported: src.count == 0 && cloud == 0 && fromChildren == 0,
                unansweredCounters: claim.counters.filter { !$0.answered }.count,
                fallen: fallen, children: children.map(\.id))
            results[claim.id] = r
            return r
        }

        let roots = map.roots.compactMap { visit($0, 0, []) }
        return summarize(map, roots, results)
    }

    static func summarize(_ map: ArgumentMap, _ roots: [ClaimResult], _ all: [String: ClaimResult]) -> Evaluation {
        guard !roots.isEmpty else {
            return Evaluation(claims: all, score: 0, grade: .empty, lean: 0, weight: 0, toppled: false, flags: Flags())
        }
        let total = roots.reduce(0) { $0 + $1.importance }
        var score = 0.0
        for r in roots { score += min(1, r.stability) * Double(r.importance) }
        score /= Double(total)

        let lean: Double
        if roots.count == 1 {
            lean = (1 - score) * K.singleLean
        } else {
            let half = roots.count / 2
            func weak(_ rs: ArraySlice<ClaimResult>) -> Double {
                rs.reduce(0) { $0 + (1 - min(1, $1.stability)) * Double($1.importance) }
            }
            let left = weak(roots.prefix(half))
            let right = weak(roots.suffix(half))
            lean = clamp((right - left) / Double(total) * K.leanScale, -K.leanMax, K.leanMax)
        }

        // Flags list claims in the map's order, like the JavaScript engine's insertion order
        // (children are scored before their parents).
        let list = orderedResults(map, all)
        var flags = Flags()
        flags.termites = list.filter { $0.termites && !$0.fallen }.map(\.id)
        flags.humble = list.filter(\.humble).map(\.id)
        flags.unsupported = list.filter { $0.unsupported && !$0.fallen }.map(\.id)
        flags.clouds = list.filter(\.cloud).count
        flags.headInClouds = flags.clouds >= 2 && Double(flags.clouds) / Double(list.count) > 1.0 / 3.0
        let counters = map.claims.reduce(0) { $0 + $1.counters.count }
        flags.cherryPicking = list.count >= 3 && counters == 0
        flags.unansweredCounters = list.reduce(0) { $0 + $1.unansweredCounters }

        return Evaluation(claims: all, score: score, grade: .from(score: score), lean: lean, weight: total,
                          toppled: score < 0.25, flags: flags)
    }

    /// Results in the order the JavaScript engine records them: depth-first, children before parents.
    static func orderedResults(_ map: ArgumentMap, _ all: [String: ClaimResult]) -> [ClaimResult] {
        var out: [ClaimResult] = []
        var seen = Set<String>()
        func walk(_ id: String) {
            guard let r = all[id], seen.insert(id).inserted else { return }
            for kid in r.children { walk(kid) }
            out.append(r)
        }
        for root in map.roots { walk(root.id) }
        return out
    }

    // MARK: Stress tests

    public struct TestOutcome: Sendable {
        public let kind: String
        public let before: Double
        public let after: Double
        public let result: Evaluation
        public let fallen: [String]
        public let toppled: Bool
    }

    static func fallenIDs(_ e: Evaluation) -> [String] {
        e.claims.values.filter(\.fallen).map(\.id).sorted()
    }

    /// A gust of wind: belief clouds blow away, and whatever they held up may fall.
    public static func wind(_ map: ArgumentMap) -> TestOutcome {
        let before = evaluate(map)
        var cond = Conditions()
        cond.removeClouds = true
        cond.fall = true
        let after = evaluate(map, cond)
        return TestOutcome(kind: "wind", before: before.score, after: after.score, result: after,
                           fallen: fallenIDs(after), toppled: after.toppled)
    }

    /// An earthquake: everything shakes, termite-eaten claims collapse, weak ones fall.
    public static func earthquake(_ map: ArgumentMap) -> TestOutcome {
        let before = evaluate(map)
        var cond = Conditions()
        cond.shake = K.quakeShake
        cond.collapseTermites = true
        cond.fall = true
        let after = evaluate(map, cond)
        return TestOutcome(kind: "earthquake", before: before.score, after: after.score, result: after,
                           fallen: fallenIDs(after), toppled: after.toppled)
    }

    // MARK: Perspective combat

    public struct SourceRemoval: Sendable, Equatable {
        public let claim: String
        /// nil when the skeptic waves off a single source.
        public let source: String?
    }

    public struct Combat: Sendable {
        public let perspective: Perspective
        public let before: Double
        public let after: Double
        public let result: Evaluation
        public let toppled: Bool
        public let sourcesOut: [SourceRemoval]
        public let cloudsOut: [String]
        public let rejected: [String]
        public let pressured: [String]
        public let attackFallen: [String]
        public let fallen: [String]
    }

    /// The opponent (1) throws out the sources it doesn't trust, (2) knocks out the premises
    /// you said it would reject, then (3) leans on everything you aren't sure of.
    public static func combat(_ map: ArgumentMap, _ p: Perspective) -> Combat {
        var base = Conditions()
        base.distrustKinds = p.distrustKinds
        base.distrustLeans = p.distrustLeans
        base.singleSourceCountsZero = p.singleSourceCountsZero
        base.removeClouds = p.removeClouds
        let before = evaluate(map)

        var sourcesOut: [SourceRemoval] = []
        let afterSources = evaluate(map, base)
        for c in map.claims {
            guard let r = afterSources.claims[c.id] else { continue }
            for sid in r.droppedSources {
                if let s = c.sources.first(where: { $0.id == sid }), map.trust(s.kind) != .distrust {
                    sourcesOut.append(SourceRemoval(claim: c.id, source: sid))
                }
            }
            if p.singleSourceCountsZero && r.sourceCount == 0 && !c.sources.isEmpty && r.droppedSources.isEmpty {
                sourcesOut.append(SourceRemoval(claim: c.id, source: nil))
            }
        }
        let cloudsOut = p.removeClouds ? map.claims.filter(\.cloud).map(\.id) : []
        let rejected = map.claims.filter { $0.disputedBy.contains(p.id) }.map(\.id)
        let pressured = map.claims.filter { !rejected.contains($0.id) && $0.confidence < K.lowConviction }.map(\.id)

        var cond = base
        cond.removed = Set(rejected)
        cond.lowConvictionPressure = K.convictionPressure
        cond.fall = true
        let after = evaluate(map, cond)
        let fallen = fallenIDs(after)
        return Combat(perspective: p, before: before.score, after: after.score, result: after, toppled: after.toppled,
                      sourcesOut: sourcesOut, cloudsOut: cloudsOut, rejected: rejected, pressured: pressured,
                      attackFallen: fallen.filter { !rejected.contains($0) }, fallen: fallen)
    }

    public struct Line: Sendable, Equatable, Hashable {
        public enum Speaker: String, Sendable { case them, narrator }
        /// 0 sources, 1 premises, 2 attack, 3 the verdict.
        public let phase: Int
        public let who: Speaker
        public let text: String
    }

    /// What the opponent says at each step.
    public static func lines(_ map: ArgumentMap, _ outcome: Combat) -> [Line] {
        let byID = Dictionary(map.claims.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let label = outcome.perspective.label
        var lines: [Line] = []
        for item in outcome.sourcesOut {
            guard let claim = byID[item.claim] else { continue }
            if let sid = item.source, let s = claim.sources.first(where: { $0.id == sid }) {
                let why = s.lean != .neutral ? "it's \(s.lean.rawValue)-leaning" : "I don't trust \(s.kind.label.lowercased())s"
                lines.append(Line(phase: 0, who: .them, text: "“\(s.title)”? I'm not taking that seriously; \(why)."))
            } else {
                lines.append(Line(phase: 0, who: .them, text: "“\(short(claim.text))” rests on one source. Find me two more."))
            }
        }
        for id in outcome.cloudsOut {
            lines.append(Line(phase: 0, who: .them, text: "You just believe “\(short(byID[id]?.text ?? ""))”. Belief isn't evidence."))
        }
        for id in outcome.rejected {
            lines.append(Line(phase: 1, who: .them, text: "I don't accept that “\(short(byID[id]?.text ?? ""))”. That pillar's gone."))
        }
        for id in outcome.pressured {
            let c = byID[id]
            lines.append(Line(phase: 2, who: .them, text: "You're only \(c?.confidence ?? 0)% sure that “\(short(c?.text ?? ""))”. Why should I be?"))
        }
        for id in outcome.attackFallen {
            lines.append(Line(phase: 2, who: .narrator, text: "“\(short(byID[id]?.text ?? ""))” gave way."))
        }
        if lines.isEmpty {
            lines.append(Line(phase: 2, who: .them, text: "I looked for a weak spot and didn't find one. Fair enough."))
        }
        lines.append(Line(phase: 3, who: .narrator, text: outcome.toppled
            ? "The \(label.lowercased()) knocked your tower over."
            : "Your tower is still standing at \(Int((outcome.after * 100).rounded()))% after the \(label.lowercased())'s attack."))
        return lines
    }

    public static func short(_ text: String, _ n: Int = 60) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > n else { return t }
        return String(t.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: Knowledge vs. conviction

    public enum Verdict: String, Sendable { case grounded, termites, humble, exploring }

    public struct Knowledge: Sendable, Equatable {
        public let id: String
        public let confidence: Int
        public let familiarity: Int
        public let verdict: Verdict
    }

    public static func knowledge(_ map: ArgumentMap) -> [Knowledge] {
        map.claims.map { c in
            var verdict = Verdict.grounded
            if hasTermites(c) { verdict = .termites } else if isHumble(c) { verdict = .humble } else if c.familiarity <= 2 { verdict = .exploring }
            return Knowledge(id: c.id, confidence: c.confidence, familiarity: c.familiarity, verdict: verdict)
        }
    }
}
