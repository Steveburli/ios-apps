import SwiftUI
import Observation
import MutualKit

/// What's on screen and who's swiping on this phone. Nothing here syncs.
@Observable
@MainActor
final class Session {
    enum Sheet: Identifiable {
        case player(String)
        case groups
        case newDeck
        case card(String)

        var id: String {
            switch self {
            case .player(let group): return "player-" + group
            case .groups: return "groups"
            case .newDeck: return "new-deck"
            case .card(let id): return "card-" + id
            }
        }
    }

    enum DeckTab: Hashable { case swipe, results, cards }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    static let readOnlyMessage = "You can look around, but changes won’t save. Ask the person who invited you to let you make changes."

    var path: [String] = []
    var sheet: Sheet?
    var toast: Toast?
    /// The tab a deck opens on, for a deck just created.
    var openingTab: [String: DeckTab] = [:]
    var currentGroupID: String? {
        didSet { UserDefaults.standard.set(currentGroupID, forKey: Keys.group) }
    }
    /// The player picker opens by itself once per launch.
    var pickerShown = false

    private var players: [String: String] {
        didSet { UserDefaults.standard.set(players, forKey: Keys.players) }
    }
    @ObservationIgnored private var undoStacks: [String: [String]] = [:]
    private(set) var undoRevision = 0

    private enum Keys {
        static let group = "mutual.group"
        static let players = "mutual.players"
    }

    init() {
        if Screenshots.isActive {
            currentGroupID = Screenshots.groupID
            players = [Screenshots.groupID: Screenshots.meID]
            pickerShown = true
            openScreenshotScreen()
            return
        }
        currentGroupID = UserDefaults.standard.string(forKey: Keys.group)
        players = UserDefaults.standard.dictionary(forKey: Keys.players) as? [String: String] ?? [:]
    }

    /// Goes to the screen named by `-screenshots`: home, swipe, results or card.
    private func openScreenshotScreen() {
        let deck = Screenshots.dateDeckID
        switch Screenshots.screen {
        case "swipe":
            path = [deck]
        case "results":
            openingTab[deck] = .results
            path = [deck]
        case "card":
            path = [deck]
            sheet = .card(Screenshots.picnicCardID)
        default:
            break
        }
    }

    /// The group on screen: the one picked, else the first.
    func group(in store: CloudStore) -> SwipeGroup? {
        if let id = currentGroupID, let group = store.groups[id] { return group }
        return store.sortedGroups.first
    }

    /// Who's swiping on this phone in a group, if they still exist.
    func me(in groupID: String, store: CloudStore) -> String? {
        guard let id = players[groupID], store.players[id] != nil else { return nil }
        return id
    }

    func setMe(_ playerID: String, in groupID: String) {
        players[groupID] = playerID
    }

    func show(_ message: String) {
        toast = Toast(message: message)
    }

    // MARK: Undo, per deck and person

    private func undoKey(_ deckID: String, _ playerID: String) -> String { deckID + "~" + playerID }

    func pushUndo(card cardID: String, deck deckID: String, player playerID: String) {
        undoStacks[undoKey(deckID, playerID), default: []].append(cardID)
        undoRevision += 1
    }

    func popUndo(deck deckID: String, player playerID: String) -> String? {
        let card = undoStacks[undoKey(deckID, playerID)]?.popLast()
        undoRevision += 1
        return card
    }

    func canUndo(deck deckID: String, player playerID: String) -> Bool {
        _ = undoRevision
        return !(undoStacks[undoKey(deckID, playerID)] ?? []).isEmpty
    }

    func clearUndo(deck deckID: String, player playerID: String) {
        undoStacks[undoKey(deckID, playerID)] = []
        undoRevision += 1
    }
}
