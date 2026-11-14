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
        /// Add many cards to a deck, or to a deck you pick when it's nil.
        case importCards(String?)
        case spin(String)
        case qr(String)
        /// Start a round on a deck.
        case startRound(String)
        /// Pick a ready-made deck, opened on one deck when given.
        case starter(String?)

        var id: String {
            switch self {
            case .player(let group): return "player-" + group
            case .groups: return "groups"
            case .newDeck: return "new-deck"
            case .card(let id): return "card-" + id
            case .importCards(let deck): return "import-" + (deck ?? "any")
            case .spin(let deck): return "spin-" + deck
            case .qr(let group): return "qr-" + group
            case .startRound(let deck): return "round-" + deck
            case .starter(let deck): return "starter-" + (deck ?? "all")
            }
        }
    }

    enum DeckTab: Hashable { case swipe, results, overlap, cards }

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
    /// Decks showing their vetting while a round is running. Rounds show by default.
    var vettingShown: Set<String> = []
    /// The player picker opens by itself once per launch.
    var pickerShown = false
    /// A file opened in Mutual from another app, waiting for the import sheet.
    var pendingImport: PendingImport?
    /// Deck ID → when this phone last saw its "just decided" banner.
    private var seenDecided: [String: Double] = [:] {
        didSet { UserDefaults.standard.set(seenDecided, forKey: Keys.seenDecided) }
    }

    private var players: [String: String] {
        didSet { UserDefaults.standard.set(players, forKey: Keys.players) }
    }
    @ObservationIgnored private var undoStacks: [String: [String]] = [:]
    private(set) var undoRevision = 0

    private enum Keys {
        static let group = "mutual.group"
        static let players = "mutual.players"
        static let seenDecided = "mutual.seenDecided"
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
        seenDecided = UserDefaults.standard.dictionary(forKey: Keys.seenDecided) as? [String: Double] ?? [:]
    }

    /// Someone else marked a card decided since this phone last looked.
    func hasNewDecision(_ deck: Deck, myName: String?) -> Bool {
        guard let at = deck.decidedAt, !deck.decidedCards.isEmpty, deck.decidedBy != myName else { return false }
        return at.timeIntervalSince1970 > (seenDecided[deck.id] ?? 0)
    }

    func markDecisionSeen(_ deck: Deck) {
        seenDecided[deck.id] = Date().timeIntervalSince1970
    }

    /// Goes to the screen named by `-screenshots` (see `Screenshots`).
    private func openScreenshotScreen() {
        let deck = Screenshots.dateDeckID
        switch Screenshots.screen {
        case "swipe":
            path = [deck]
        case "results":
            openingTab[deck] = .results
            path = [deck]
        case "overlap":
            openingTab[deck] = .overlap
            path = [deck]
        case "card":
            path = [deck]
            sheet = .card(Screenshots.picnicCardID)
        case "import":
            openingTab[deck] = .cards
            path = [deck]
            pendingImport = PendingImport(text: Screenshots.importSample, name: "Sample", isCSV: false)
            sheet = .importCards(deck)
        case "spin":
            openingTab[deck] = .results
            path = [deck]
            sheet = .spin(deck)
        case "round":
            path = [Screenshots.dinnerDeckID]
        case "roundresults":
            openingTab[Screenshots.dinnerDeckID] = .results
            path = [Screenshots.dinnerDeckID]
        case "startround":
            path = [deck]
            sheet = .startRound(deck)
        case "starter":
            sheet = .starter(nil)
        case "starterpreview":
            sheet = .starter("dinners")
        case "starterswipe":
            path = [Screenshots.starterDeckID]
        default:
            break
        }
    }

    /// Whether a deck shows its round (true) or its vetting (false).
    func showsRound(_ deck: Deck) -> Bool {
        deck.activeRound != nil && !vettingShown.contains(deck.id)
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
