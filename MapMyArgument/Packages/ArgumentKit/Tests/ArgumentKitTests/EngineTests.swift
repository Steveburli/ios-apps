import XCTest
@testable import ArgumentKit

final class EngineTests: XCTestCase {
    func claim(_ id: String, parent: String? = nil, importance: Int = 3, confidence: Int = 60, familiarity: Int = 3,
               cloud: Bool = false, sources: [Source] = [], disputedBy: [String] = []) -> Claim {
        Claim(id: id, parent: parent, text: id, importance: importance, confidence: confidence, familiarity: familiarity,
              cloud: cloud, sources: sources, disputedBy: disputedBy)
    }

    func src(_ id: String, _ kind: SourceKind = .study, title: String? = nil, lean: Lean = .neutral) -> Source {
        Source(id: id, title: title ?? id, kind: kind, lean: lean)
    }

    func testMoreIndependentSourcesAreStrongerUpToThree() {
        let map = ArgumentMap(trust: ["study": .trust], claims: [
            claim("one", sources: [src("a")]),
            claim("two", sources: [src("a"), src("b")]),
            claim("three", sources: [src("a"), src("b"), src("c")]),
            claim("four", sources: [src("a"), src("b"), src("c"), src("d")]),
        ])
        let r = Engine.evaluate(map).claims
        XCTAssertEqual(r["one"]?.tier, "I")
        XCTAssertEqual(r["two"]?.tier, "II")
        XCTAssertEqual(r["three"]?.tier, "IXI")
        XCTAssertLessThan(r["one"]!.strength, r["two"]!.strength)
        XCTAssertLessThan(r["two"]!.strength, r["three"]!.strength)
        XCTAssertEqual(r["three"]!.strength, r["four"]!.strength, accuracy: 1e-9)
    }

    func testSameTitleCountsOnce() {
        let map = ArgumentMap(claims: [claim("c", sources: [src("a", title: "Report"), src("b", title: " report ")])])
        XCTAssertEqual(Engine.evaluate(map).claims["c"]?.tier, "I")
    }

    func testTermitesHollowOutConfidentClaimsYouHaventResearched() {
        let solid = ArgumentMap(claims: [claim("c", confidence: 90, familiarity: 4, sources: [src("a")])])
        let hollow = ArgumentMap(claims: [claim("c", confidence: 90, familiarity: 1, sources: [src("a")])])
        let a = Engine.evaluate(solid).claims["c"]!, b = Engine.evaluate(hollow).claims["c"]!
        XCTAssertTrue(b.termites)
        XCTAssertEqual(b.strength, a.strength * K.termiteFactor, accuracy: 1e-9)
    }

    func testWindBlowsAwayBeliefClouds() {
        let map = ArgumentMap(trust: ["study": .trust], claims: [
            claim("c", importance: 5, cloud: true),
            claim("d", sources: [src("a"), src("b")]),
        ])
        let w = Engine.wind(map)
        XCTAssertEqual(w.fallen, ["c"])
        XCTAssertLessThan(w.after, w.before)
    }

    func testOpponentDropsDistrustedSourcesAndRejectedPremises() {
        let map = ArgumentMap(trust: ["news": .trust, "study": .trust], claims: [
            claim("c", sources: [src("a", .news, lean: .left), src("b", .news, lean: .right)]),
            claim("d", sources: [src("e")], disputedBy: ["conservative"]),
        ])
        let o = Engine.combat(map, Perspective.find("conservative")!)
        XCTAssertEqual(o.sourcesOut, [Engine.SourceRemoval(claim: "c", source: "a")])
        XCTAssertEqual(o.rejected, ["d"])
        XCTAssertTrue(o.fallen.contains("d"))
        XCTAssertTrue(Engine.lines(map, o).contains { $0.text.contains("left-leaning") })
    }

    func testEmptyMapIsAnEmptyLot() {
        let e = Engine.evaluate(ArgumentMap())
        XCTAssertEqual(e.grade.id, "empty")
        XCTAssertFalse(e.toppled)
    }

    func testOutlineLabels() {
        let map = ArgumentMap(claims: [claim("a"), claim("b"), claim("b1", parent: "b"), claim("b2", parent: "b")])
        XCTAssertEqual(map.outline.map(\.label), ["1", "2", "2a", "2b"])
        var copy = map
        copy.removeClaim("b")
        XCTAssertEqual(copy.claims.map(\.id), ["a"])
    }

    func testShareCodesRoundTrip() throws {
        var map = Catalog.example
        map.thesis = "Café ☕ means “coffee”"
        let back = try ShareCode.decode(ShareCode.encode(map))
        XCTAssertEqual(back, map)
        XCTAssertThrowsError(try ShareCode.decode("hello"))
        XCTAssertThrowsError(try ShareCode.decode("MMA1.!!!"))
    }

    func testDecodingRepairsBadInput() throws {
        let json = #"{"stance":"maybe","claims":[{"importance":99,"confidence":-5,"sources":[{"kind":"tabloid","lean":"up"}],"disputedBy":["martian","skeptic"]}]}"#
        let map = try JSONDecoder().decode(ArgumentMap.self, from: Data(json.utf8))
        XCTAssertEqual(map.stance, .unsure)
        XCTAssertEqual(map.claims[0].importance, 5)
        XCTAssertEqual(map.claims[0].confidence, 0)
        XCTAssertEqual(map.claims[0].sources[0].kind, .news)
        XCTAssertEqual(map.claims[0].sources[0].lean, .neutral)
        XCTAssertEqual(map.claims[0].disputedBy, ["skeptic"])
    }

    func testCatalogLoads() {
        XCTAssertEqual(Catalog.example.claims.count, 5)
        XCTAssertEqual(Catalog.exampleFriend.claims.count, 6)
        XCTAssertFalse(Catalog.topics.isEmpty)
    }
}
