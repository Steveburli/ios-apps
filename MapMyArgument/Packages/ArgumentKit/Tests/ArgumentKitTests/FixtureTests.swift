import XCTest
@testable import ArgumentKit

/// Checks the Swift engine against the shared cases made from the JavaScript engine
/// (tools/make-fixtures.mjs), so the app and the website score every map the same way.
final class FixtureTests: XCTestCase {
    static let cases: [String: Any] = {
        guard let url = Bundle.module.url(forResource: "engine-cases", withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }()

    func decodeMap(_ any: Any?) throws -> ArgumentMap {
        let data = try JSONSerialization.data(withJSONObject: any ?? [:])
        return try JSONDecoder().decode(ArgumentMap.self, from: data)
    }

    func num(_ any: Any?) -> Double { (any as? NSNumber)?.doubleValue ?? .nan }

    func close(_ a: Double, _ b: Double, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 1e-6, message, file: file, line: line)
    }

    func testFixturesLoaded() {
        XCTAssertFalse((Self.cases["maps"] as? [Any] ?? []).isEmpty, "engine-cases.json is missing from the test bundle")
    }

    func testEvaluateMatchesTheWebsite() throws {
        for case let c as [String: Any] in Self.cases["maps"] as? [Any] ?? [] {
            let name = c["name"] as? String ?? "?"
            let map = try decodeMap(c["map"])
            let expect = (c["expect"] as? [String: Any])?["evaluate"] as? [String: Any] ?? [:]
            let e = Engine.evaluate(map)
            close(e.score, num(expect["score"]), "\(name) score")
            XCTAssertEqual(e.grade.id, expect["grade"] as? String, name)
            close(e.lean, num(expect["lean"]), "\(name) lean")
            XCTAssertEqual(e.weight, (expect["weight"] as? NSNumber)?.intValue, name)
            XCTAssertEqual(e.toppled, expect["toppled"] as? Bool, name)

            let flags = expect["flags"] as? [String: Any] ?? [:]
            XCTAssertEqual(e.flags.termites, flags["termites"] as? [String], "\(name) termites")
            XCTAssertEqual(e.flags.humble, flags["humble"] as? [String], "\(name) humble")
            XCTAssertEqual(e.flags.unsupported, flags["unsupported"] as? [String], "\(name) unsupported")
            XCTAssertEqual(e.flags.headInClouds, flags["headInClouds"] as? Bool, "\(name) headInClouds")
            XCTAssertEqual(e.flags.clouds, (flags["clouds"] as? NSNumber)?.intValue, "\(name) clouds")
            XCTAssertEqual(e.flags.cherryPicking, flags["cherryPicking"] as? Bool, "\(name) cherryPicking")
            XCTAssertEqual(e.flags.unansweredCounters, (flags["unansweredCounters"] as? NSNumber)?.intValue, "\(name) counters")

            let claims = expect["claims"] as? [String: Any] ?? [:]
            XCTAssertEqual(Set(e.claims.keys), Set(claims.keys), "\(name) scored claims")
            for (id, any) in claims {
                let x = any as? [String: Any] ?? [:]
                guard let r = e.claims[id] else { XCTFail("\(name)/\(id) missing"); continue }
                close(r.strength, num(x["strength"]), "\(name)/\(id) strength")
                close(r.stability, num(x["stability"]), "\(name)/\(id) stability")
                XCTAssertEqual(r.status.rawValue, x["status"] as? String, "\(name)/\(id) status")
                XCTAssertEqual(r.tier, x["tier"] as? String, "\(name)/\(id) tier")
                XCTAssertEqual(r.sourceCount, (x["sourceCount"] as? NSNumber)?.intValue, "\(name)/\(id) sources")
                XCTAssertEqual(r.termites, x["termites"] as? Bool, "\(name)/\(id) termites")
                XCTAssertEqual(r.humble, x["humble"] as? Bool, "\(name)/\(id) humble")
                XCTAssertEqual(r.unsupported, x["unsupported"] as? Bool, "\(name)/\(id) unsupported")
                XCTAssertEqual(r.cloud, x["cloud"] as? Bool, "\(name)/\(id) cloud")
                XCTAssertEqual(r.depth, (x["depth"] as? NSNumber)?.intValue, "\(name)/\(id) depth")
            }
        }
    }

    func testStressTestsMatchTheWebsite() throws {
        for case let c as [String: Any] in Self.cases["maps"] as? [Any] ?? [] {
            let name = c["name"] as? String ?? "?"
            let map = try decodeMap(c["map"])
            let expect = c["expect"] as? [String: Any] ?? [:]
            for (key, outcome) in [("wind", Engine.wind(map)), ("earthquake", Engine.earthquake(map))] {
                let x = expect[key] as? [String: Any] ?? [:]
                close(outcome.after, num(x["after"]), "\(name) \(key)")
                XCTAssertEqual(outcome.fallen, x["fallen"] as? [String], "\(name) \(key) fallen")
                XCTAssertEqual(outcome.toppled, x["toppled"] as? Bool, "\(name) \(key) toppled")
            }
            let combat = expect["combat"] as? [String: Any] ?? [:]
            for p in Perspective.all {
                let x = combat[p.id] as? [String: Any] ?? [:]
                let o = Engine.combat(map, p)
                close(o.after, num(x["after"]), "\(name) vs \(p.id)")
                XCTAssertEqual(o.fallen, x["fallen"] as? [String], "\(name) vs \(p.id) fallen")
                XCTAssertEqual(o.toppled, x["toppled"] as? Bool, "\(name) vs \(p.id) toppled")
                XCTAssertEqual(o.rejected, x["premises"] as? [String], "\(name) vs \(p.id) premises")
                XCTAssertEqual(o.pressured, x["attack"] as? [String], "\(name) vs \(p.id) attack")
                XCTAssertEqual(o.attackFallen.sorted(), x["attackFallen"] as? [String], "\(name) vs \(p.id) attack fallen")
                XCTAssertEqual(o.cloudsOut, x["clouds"] as? [String], "\(name) vs \(p.id) clouds")
                let sources = (x["sources"] as? [[String: Any]] ?? []).map {
                    Engine.SourceRemoval(claim: $0["claim"] as? String ?? "", source: $0["source"] as? String)
                }
                XCTAssertEqual(o.sourcesOut, sources, "\(name) vs \(p.id) sources")
            }
            let knowledge = expect["knowledge"] as? [[String: Any]] ?? []
            XCTAssertEqual(Engine.knowledge(map).map(\.verdict.rawValue), knowledge.map { $0["verdict"] as? String ?? "" }, "\(name) knowledge")
        }
    }

    func testCompareMatchesTheWebsite() throws {
        for case let c as [String: Any] in Self.cases["compares"] as? [Any] ?? [] {
            let name = c["name"] as? String ?? "?"
            let result = Compare.run(try decodeMap(c["mine"]), try decodeMap(c["theirs"]))
            let x = c["expect"] as? [String: Any] ?? [:]
            XCTAssertEqual(result.sameStance, x["sameStance"] as? Bool, name)
            XCTAssertEqual(result.agreeCount, (x["agreeCount"] as? NSNumber)?.intValue, name)
            XCTAssertEqual(result.disagreeCount, (x["disagreeCount"] as? NSNumber)?.intValue, name)
            XCTAssertEqual(result.degreeCount, (x["degreeCount"] as? NSNumber)?.intValue, name)
            XCTAssertEqual(result.onlyMine, x["onlyMine"] as? [String], name)
            XCTAssertEqual(result.onlyTheirs, x["onlyTheirs"] as? [String], name)
            XCTAssertEqual(result.queue.map(\.mine), x["queue"] as? [String], "\(name) queue")
            let items = x["items"] as? [[String: Any]] ?? []
            XCTAssertEqual(result.items.map(\.mine), items.map { $0["mine"] as? String ?? "" }, name)
            XCTAssertEqual(result.items.map(\.theirs), items.map { $0["theirs"] as? String ?? "" }, name)
            XCTAssertEqual(result.items.map(\.kind.rawValue), items.map { $0["kind"] as? String ?? "" }, name)
            for (item, expected) in zip(result.items, items) {
                close(item.match, num(expected["match"]), "\(name) match")
                XCTAssertEqual(item.conflicts.map(\.source), (expected["conflicts"] as? [[String: Any]] ?? []).map { $0["source"] as? String ?? "" })
            }
            let split = x["trustSplit"] as? [[String: Any]] ?? []
            XCTAssertEqual(result.trustSplit.map(\.kind.rawValue), split.map { $0["kind"] as? String ?? "" }, name)
        }
    }

    func testSimilarityMatchesTheWebsite() {
        for case let s as [String: Any] in Self.cases["similarity"] as? [Any] ?? [] {
            close(Compare.similarity(s["a"] as? String ?? "", s["b"] as? String ?? ""), num(s["value"]), "similarity")
        }
    }

    func testReadsAShareCodeMadeByTheWebsite() throws {
        let share = Self.cases["shareCode"] as? [String: Any] ?? [:]
        let map = try ShareCode.decode("Here you go: " + (share["code"] as? String ?? ""))
        XCTAssertEqual(map.claims.count, (share["claims"] as? NSNumber)?.intValue)
        XCTAssertEqual(map.thesis, share["thesis"] as? String)
        XCTAssertEqual(map.id, Catalog.example.id)
    }
}
