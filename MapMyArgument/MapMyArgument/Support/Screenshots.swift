import Foundation
import ArgumentKit

/// The cloud build launches the app with `-screenshots <screen>` to photograph each screen
/// with sample data: home, build, survey, map, test, combat, rate, compare or how. Nothing
/// here runs in normal use, and the sample store never saves.
enum Screenshots {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool { screen != nil }

    /// The example map as the person's own, so every editing control shows.
    static var sampleMap: ArgumentMap {
        var map = Catalog.example
        map.id = "sample-map"
        map.author = "Alex"
        return map
    }

    /// A half-built spork argument for the builder screens.
    static var sampleDraft: ArgumentMap {
        ArgumentMap(
            id: "sample-draft", topic: "The spork is an inferior utensil", thesis: "The spork is an inferior utensil",
            stance: .for, author: "Alex",
            trust: ["study": .trust, "government": .trust, "news": .unfamiliar, "social": .distrust],
            claims: [
                Claim(id: "d1", text: "A spork does neither job well: it spills soup and fails at stabbing", importance: 5,
                      confidence: 80, familiarity: 3,
                      sources: [Source(id: "ds1", title: "Consumer utensil test", kind: .study),
                                Source(id: "ds2", title: "Cooking magazine column", kind: .news)],
                      counters: [Counter(id: "dx1", text: "Sporks are great for camping", strength: 3)]),
                Claim(id: "d2", text: "Nobody keeps sporks in a real kitchen drawer", importance: 3, confidence: 95, familiarity: 1, cloud: true),
                Claim(id: "d3", text: "Sporks exist because they're cheap, not because they're good", importance: 3, confidence: 60),
                Claim(id: "d3a", parent: "d3", text: "Fast food chains buy them by the million", importance: 3, confidence: 70,
                      sources: [Source(id: "ds3", title: "Restaurant supply catalog", kind: .reference)]),
            ])
    }

    static func store() -> Store {
        let store = Store(saves: false)
        store.name = "Alex"
        store.trust = sampleDraft.trust
        store.maps = [sampleMap]
        switch screen {
        case "build":
            store.draft = sampleDraft
            store.draftStep = 4
            store.path = [.build]
        case "survey":
            store.draft = sampleDraft
            store.draftStep = 5
            store.path = [.build]
        case "map", "test", "combat":
            store.path = [.map(sampleMap.id)]
        case "rate":
            var theirs = sampleDraft
            theirs.id = "sam-spork"
            theirs.author = "Sam"
            store.name = "Jordan"
            _ = try? store.receive(ShareCode.encode(theirs))
            store.path = [.rate]
        case "compare":
            store.comparison = Comparison(mine: Catalog.example, theirs: Catalog.exampleFriend, meLabel: "You", canAdopt: false)
            store.path = [.compare]
        case "how":
            store.path = [.how]
        default:
            break
        }
        return store
    }
}
