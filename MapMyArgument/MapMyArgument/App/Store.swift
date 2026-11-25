import SwiftUI
import Observation
import ArgumentKit

/// Where the app's screens are.
enum Route: Hashable {
    case map(String)
    case build
    case rate
    case compare
    case how
}

/// A friend's map waiting to be rated: theirs, and my answers so far.
struct Rating {
    var theirs: ArgumentMap
    var mine: ArgumentMap
}

/// Two maps side by side. `canAdopt` is true when `mine` is my own map (so their reasons
/// and agreement can be added to it); `replyCode` is set when I just rated their map.
struct Comparison {
    var mine: ArgumentMap
    var theirs: ArgumentMap
    var meLabel = "You"
    var canAdopt = false
    var replyCode = ""
}

/// Owns the maps and saves them as JSON in UserDefaults (`maps.v1`). Nothing leaves the
/// phone unless the person shares a code.
@Observable
final class Store {
    var maps: [ArgumentMap] = []
    /// The last answers to "which sources do you trust?", used to start each new map.
    var trust: [String: Trust] = [:]
    var name = ""
    /// The map being built, kept so it survives the app closing.
    var draft: ArgumentMap?
    var draftStep = 0

    var path: [Route] = []
    var rating: Rating?
    var comparison: Comparison?

    private let key = "maps.v1"
    private let saves: Bool

    struct Saved: Codable {
        var maps: [ArgumentMap]
        var trust: [String: Trust]
        var name: String
        var draft: ArgumentMap?
        var draftStep: Int
    }

    init(saves: Bool = true) {
        self.saves = saves
        guard saves, let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        maps = saved.maps
        trust = saved.trust
        name = saved.name
        draft = saved.draft
        draftStep = saved.draftStep
    }

    func save() {
        guard saves else { return }
        let saved = Saved(maps: maps, trust: trust, name: name, draft: draft, draftStep: draftStep)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: Maps

    func map(_ id: String) -> ArgumentMap? {
        if id == Catalog.example.id { return Catalog.example }
        return maps.first { $0.id == id }
    }

    func isExample(_ id: String) -> Bool { id == Catalog.example.id }

    func upsert(_ map: ArgumentMap) {
        var map = map
        map.updated = Ids.now()
        if let i = maps.firstIndex(where: { $0.id == map.id }) {
            maps[i] = map
        } else {
            maps.insert(map, at: 0)
        }
        save()
    }

    func delete(_ id: String) {
        maps.removeAll { $0.id == id }
        save()
    }

    /// A binding that edits a saved map in place.
    func binding(for id: String) -> Binding<ArgumentMap> {
        Binding(
            get: { self.map(id) ?? ArgumentMap(id: id) },
            set: { self.upsert($0) })
    }

    /// A binding to the map being built.
    var draftBinding: Binding<ArgumentMap> {
        Binding(
            get: { self.draft ?? ArgumentMap() },
            set: { self.draft = $0; self.save() })
    }

    // MARK: Building

    func startDraft(topic: String = "") {
        draft = ArgumentMap(topic: topic, thesis: topic, stance: .for, author: name, trust: trust)
        draftStep = 0
        save()
    }

    /// Saves the finished draft as a map and returns its id.
    func construct() -> String? {
        guard var map = draft else { return nil }
        map.claims.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if map.author.isEmpty { map.author = name }
        upsert(map)
        draft = nil
        draftStep = 0
        save()
        return map.id
    }

    func copyExample() -> String {
        var copy = Catalog.example
        copy.id = Ids.make("map")
        copy.author = name
        copy.created = Ids.now()
        upsert(copy)
        return copy.id
    }

    /// Opens a draft that edits an existing map's position and sources.
    func editPosition(of id: String) {
        guard let map = map(id) else { return }
        draft = map
        draftStep = 1
        save()
    }

    // MARK: Sharing

    func shareCode(for map: ArgumentMap) -> String {
        var copy = map
        if !name.isEmpty { copy.author = name }
        return ShareCode.encode(copy)
    }

    enum Received {
        case rate
        case compare
        case alreadyHave(String)
    }

    /// Opens a code from a friend: their answer to one of my maps (compare), a map I already
    /// have (open it), or someone else's map (rate it).
    func receive(_ code: String) throws -> Received {
        let theirs = try ShareCode.decode(code)
        if let original = maps.first(where: { $0.id == theirs.basedOn && $0.basedOn.isEmpty }) {
            comparison = Comparison(mine: original, theirs: theirs, canAdopt: true)
            return .compare
        }
        if maps.contains(where: { $0.id == theirs.id }) {
            return .alreadyHave(theirs.id)
        }
        var mine = theirs
        mine.id = Ids.make("map")
        mine.basedOn = theirs.id
        mine.author = name
        mine.trust = trust
        mine.stance = .unsure
        mine.counted = []
        mine.created = Ids.now()
        mine.claims = theirs.claims.map { c in
            var c = c
            c.confidence = 50
            c.familiarity = 3
            c.votes = 0
            c.counters = []
            c.disputedBy = []
            c.cloud = false
            c.sources = []
            return c
        }
        rating = Rating(theirs: theirs, mine: mine)
        return .rate
    }

    /// Saves my rating, keeps a copy of their map, and opens the comparison with a code to send back.
    func finishRating() {
        guard var rating else { return }
        rating.mine.claims.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        rating.mine.author = name.isEmpty ? "Friend" : name
        let theirs = rating.theirs
        switch rating.mine.stance {
        case theirs.stance: rating.mine.thesis = theirs.thesis
        case .unsure: rating.mine.thesis = "Not sure: " + theirs.topic
        default: rating.mine.thesis = "Not convinced: " + (theirs.thesis.isEmpty ? theirs.topic : theirs.thesis)
        }
        upsert(rating.mine)
        if !maps.contains(where: { $0.id == theirs.id }) {
            maps.append(theirs)
            save()
        }
        comparison = Comparison(mine: rating.mine, theirs: theirs, canAdopt: false, replyCode: ShareCode.encode(rating.mine))
        self.rating = nil
    }

    /// Adds one vote to each of my claims the other person agrees with, once per rating.
    func countVotes() -> Int {
        guard var comparison, comparison.canAdopt, !comparison.mine.counted.contains(comparison.theirs.id) else { return 0 }
        let result = Compare.run(comparison.mine, comparison.theirs)
        var n = 0
        for item in result.items where item.theirConfidence >= 50 {
            if let i = comparison.mine.index(of: item.mine) {
                comparison.mine.claims[i].votes += 1
                n += 1
            }
        }
        comparison.mine.counted.append(comparison.theirs.id)
        upsert(comparison.mine)
        self.comparison = comparison
        return n
    }

    func adopt(_ claimID: String) {
        guard var comparison, comparison.canAdopt,
              var claim = comparison.theirs.claims.first(where: { $0.id == claimID }) else { return }
        claim.id = Ids.make("c")
        claim.parent = nil
        claim.confidence = 50
        claim.votes = 1
        claim.counters = []
        claim.disputedBy = []
        comparison.mine.claims.append(claim)
        upsert(comparison.mine)
        self.comparison = comparison
    }
}

extension Binding where Value == ArgumentMap {
    /// A binding to one claim inside the map.
    func claim(_ id: String) -> Binding<Claim> {
        Binding<Claim>(
            get: { self.wrappedValue.claims.first { $0.id == id } ?? Claim(id: id) },
            set: { newValue in
                var map = self.wrappedValue
                if let i = map.index(of: id) {
                    map.claims[i] = newValue
                    self.wrappedValue = map
                }
            })
    }
}
