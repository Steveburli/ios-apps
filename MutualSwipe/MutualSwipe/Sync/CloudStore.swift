import Foundation
import CloudKit
import Observation
import MutualKit

/// All groups, decks, cards, players and picks, kept in a local file and
/// synced with iCloud by two CKSyncEngines: one for the groups you own (your
/// private database) and one for groups shared with you (the shared database).
///
/// The UI reads and writes here and never waits on the network. Changes are
/// queued with the engines, which send them when they can.
@Observable
@MainActor
final class CloudStore: CKSyncEngineDelegate {
    static let shared = CloudStore()
    static let containerID = "iCloud.com.steveburlison.mutualswipe"

    private(set) var groups: [String: SwipeGroup] = [:]
    private(set) var decks: [String: Deck] = [:]
    private(set) var cards: [String: Card] = [:]
    private(set) var players: [String: Player] = [:]
    private(set) var picks: [String: Pick] = [:]
    /// Everyone's answers to deck questions, by record name.
    private(set) var answers: [String: FormAnswers] = [:]
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    private(set) var isSyncing = false
    /// A message for the person, shown once as a toast.
    var notice: String?
    /// The group just joined from an invitation, so the UI can switch to it.
    var joinedGroupID: String?

    @ObservationIgnored private var cachedContainer: CKContainer?
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    @ObservationIgnored private var privateState: CKSyncEngine.State.Serialization?
    @ObservationIgnored private var sharedState: CKSyncEngine.State.Serialization?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        var groups: [SwipeGroup] = []
        var decks: [Deck] = []
        var cards: [Card] = []
        var players: [Player] = []
        var picks: [Pick] = []
        /// Optional so files saved before deck questions still load.
        var answers: [FormAnswers]?
        var privateState: CKSyncEngine.State.Serialization?
        var sharedState: CKSyncEngine.State.Serialization?
    }

    private init() {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("mutual.json")
        if Screenshots.isActive {
            // Unsigned screenshot builds have no iCloud access, so use sample decks instead.
            loadScreenshotData()
            return
        }
        load()
        startEngines()
        Task { await refreshAccountStatus() }
    }

    /// Made on first use. Screenshot builds never touch it, because they aren't entitled to iCloud.
    var container: CKContainer {
        if let cachedContainer { return cachedContainer }
        let made = CKContainer(identifier: Self.containerID)
        cachedContainer = made
        return made
    }

    var isSignedIn: Bool {
        accountStatus == .available
    }

    // MARK: Reading

    /// Your own groups first, oldest first, then groups shared with you.
    var sortedGroups: [SwipeGroup] {
        groups.values.sorted { a, b in
            if a.isOwned != b.isOwned { return a.isOwned }
            return (a.createdAt, a.id) < (b.createdAt, b.id)
        }
    }

    /// Newest first, like the web app.
    func decks(in groupID: String) -> [Deck] {
        decks.values.filter { $0.groupID == groupID }.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    /// The deck's cards, leaving out ones marked "Never, for good".
    func cards(in deckID: String) -> [Card] {
        cards.values.filter { $0.deckID == deckID && !$0.isRetired }.inSwipeOrder()
    }

    func retiredCards(in deckID: String) -> [Card] {
        cards.values.filter { $0.deckID == deckID && $0.isRetired }.inSwipeOrder()
    }

    func players(in groupID: String) -> [Player] {
        players.values.filter { $0.groupID == groupID }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The deck's vetting: everyone's first pass, outside any round.
    func state(of deckID: String, me: String?) -> DeckState {
        let deck = decks[deckID]
        let deckPicks = picks.values.filter { $0.deckID == deckID && $0.roundID == nil }
        return DeckState(cards: cards(in: deckID), players: deck.map { players(in: $0.groupID) } ?? [],
                         picks: Array(deckPicks), me: me)
    }

    /// The round running on a deck, with only that round's cards and votes.
    func roundState(of deckID: String, me: String?) -> DeckState? {
        guard let deck = decks[deckID], let round = deck.activeRound else { return nil }
        let inRound = Set(deck.roundCards ?? [])
        let roundPicks = picks.values.filter { $0.deckID == deckID && $0.roundID == round }
        return DeckState(cards: cards(in: deckID).filter { inRound.contains($0.id) }, players: players(in: deck.groupID),
                         picks: Array(roundPicks), me: me)
    }

    /// The round when one is running and on screen, else vetting.
    func liveState(of deckID: String, me: String?, vetting: Bool) -> DeckState {
        if !vetting, let round = roundState(of: deckID, me: me) { return round }
        return state(of: deckID, me: me)
    }

    /// Each person's share of the deck vetted.
    func vetting(of deckID: String) -> Vetting {
        let groupID = decks[deckID]?.groupID ?? ""
        return Vetting(state: state(of: deckID, me: nil), players: players(in: groupID).map { $0.id })
    }

    /// One person's answers to a deck's questions, if they have any.
    func answers(deck deckID: String, player playerID: String) -> FormAnswers? {
        answers[FormAnswers.id(deckID: deckID, playerID: playerID)]
    }

    /// Whether this person still has to fill in or confirm the deck's questions.
    func needsAnswers(deck deckID: String, player playerID: String?) -> Bool {
        guard let playerID, let deck = decks[deckID] else { return false }
        return Forms.needsAnswers(questions: deck.formQuestions, answers: answers(deck: deckID, player: playerID))
    }

    func canWrite(_ groupID: String) -> Bool {
        !(groups[groupID]?.readOnly ?? true)
    }

    // MARK: Groups

    /// Makes your first group the first time it's needed.
    @discardableResult
    func ensureGroup() -> SwipeGroup {
        if let first = sortedGroups.first { return first }
        return createGroup(named: "Our decks")
    }

    @discardableResult
    func createGroup(named name: String) -> SwipeGroup {
        let id = "group-" + makeID()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = SwipeGroup(id: id, ownerName: CKCurrentUserDefaultName, name: trimmed.isEmpty ? "Our decks" : String(trimmed.prefix(40)),
                               isOwned: true, createdAt: Date())
        groups[id] = group
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID(for: group)))])
        enqueueSave(Records.groupRecordName, in: group)
        scheduleSave()
        return group
    }

    func renameGroup(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var group = groups[id], group.isOwned, !trimmed.isEmpty else { return }
        group.name = String(trimmed.prefix(40))
        groups[id] = group
        enqueueSave(Records.groupRecordName, in: group)
        scheduleSave()
    }

    /// Deletes a group you own (and stops sharing it), or leaves one shared with you.
    func removeGroup(_ id: String) {
        guard let group = groups[id] else { return }
        let zone = zoneID(for: group)
        engine(for: group)?.state.add(pendingDatabaseChanges: [.deleteZone(zone)])
        dropGroup(id)
        scheduleSave()
    }

    // MARK: Decks and cards

    func createDeck(in groupID: String, title: String, kind: DeckKind, blurb: String) -> Deck? {
        guard let group = groups[groupID] else { return nil }
        let deck = Deck(groupID: groupID, title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)), kind: kind,
                        blurb: String(blurb.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)), createdAt: Date())
        decks[deck.id] = deck
        enqueueSave(deck.id, in: group)
        scheduleSave()
        return deck
    }

    func updateDeck(_ id: String, title: String, blurb: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var deck = decks[id], let group = groups[deck.groupID], !trimmed.isEmpty else { return }
        deck.title = String(trimmed.prefix(60))
        deck.blurb = String(blurb.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
        decks[id] = deck
        enqueueSave(id, in: group)
        scheduleSave()
    }

    /// The server deletes the deck's cards and picks along with it.
    func deleteDeck(_ id: String) {
        guard let deck = decks[id], let group = groups[deck.groupID] else { return }
        enqueueDelete(id, in: group)
        removeDeckLocally(id)
        scheduleSave()
    }

    /// Returns how many were added.
    @discardableResult
    func addCards(_ drafts: [CardDraft], to deckID: String) -> Int {
        addCardIDs(drafts, to: deckID).count
    }

    /// Adds cards and returns the new cards' IDs.
    @discardableResult
    private func addCardIDs(_ drafts: [CardDraft], to deckID: String) -> [String] {
        guard let deck = decks[deckID], let group = groups[deck.groupID] else { return [] }
        let base = Date().timeIntervalSince1970 * 1000
        var added: [String] = []
        for (i, draft) in drafts.enumerated() {
            guard let clean = CardText.clean(draft) else { continue }
            let card = Card(groupID: group.id, deckID: deckID, draft: clean, order: base + Double(i), createdAt: Date())
            cards[card.id] = card
            enqueueSave(card.id, in: group)
            added.append(card.id)
        }
        scheduleSave()
        return added
    }

    // MARK: Deck questions

    /// Replaces a deck's questions. Answers to removed questions stay saved
    /// but aren't shown.
    func setQuestions(_ questions: [FormQuestion], deck deckID: String) {
        guard var deck = decks[deckID], let group = groups[deck.groupID] else { return }
        deck.questions = Array(questions.compactMap { $0.cleaned() }.prefix(30))
        decks[deckID] = deck
        enqueueSave(deckID, in: group)
        scheduleSave()
    }

    /// What happened when someone saved answers.
    struct AnswerResult {
        /// New cards made from the person's ideas.
        var newCards = 0
        /// Ideas that were already cards, which got their Love instead.
        var matched = 0
    }

    /// Saves a person's answers. When they save their own, that confirms
    /// them, and their ideas become cards with a Love from them. When someone
    /// fills in for them, the answers wait for them to look over and confirm.
    @discardableResult
    func saveAnswers(_ values: [String: String], deck deckID: String, player playerID: String, by me: String) -> AnswerResult {
        guard let deck = decks[deckID], let group = groups[deck.groupID] else { return AnswerResult() }
        let questions = deck.formQuestions
        let asked = Set(questions.map(\.id))
        var kept: [String: String] = [:]
        for (key, value) in values where asked.contains(key) {
            let trimmed = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
            if !trimmed.isEmpty { kept[key] = trimmed }
        }
        let id = FormAnswers.id(deckID: deckID, playerID: playerID)
        var saved = answers[id] ?? FormAnswers(groupID: group.id, deckID: deckID, playerID: playerID, filledBy: me, updatedAt: Date())
        // Answers to questions taken off the deck stay as they were.
        for (key, value) in saved.values where !asked.contains(key) { kept[key] = value }
        saved.values = kept
        saved.filledBy = me
        saved.updatedAt = Date()
        saved.confirmedAt = me == playerID ? Date() : nil
        var result = AnswerResult()
        if me == playerID {
            let plan = Forms.ideaPlan(questions: questions, values: kept, alreadyMade: saved.ideasMade,
                                      cards: cards.values.filter { $0.deckID == deckID }.inSwipeOrder())
            saved.ideasMade = plan.made
            let name = players[playerID]?.name ?? ""
            let drafts = plan.newCards.map { CardDraft(title: $0, subtitle: Forms.ideaSubtitle(by: name), tags: ["idea"]) }
            let made = addCardIDs(drafts, to: deckID)
            for cardID in made + plan.matchingCards {
                setVote(.love, card: cardID, player: playerID)
            }
            result.newCards = made.count
            result.matched = plan.matchingCards.count
        }
        answers[id] = saved
        enqueueSave(id, in: group)
        scheduleSave()
        return result
    }

    func deleteCard(_ id: String) {
        guard let card = cards[id], let group = groups[card.groupID] else { return }
        enqueueDelete(id, in: group)
        cards[id] = nil
        picks = picks.filter { $0.value.cardID != id }
        scheduleSave()
    }

    // MARK: After a match

    /// Marks a card as decided for the whole group, or takes it back.
    func setDecided(_ isDecided: Bool, card cardID: String, by name: String?) {
        guard let card = cards[cardID], var deck = decks[card.deckID], let group = groups[deck.groupID] else { return }
        var list = deck.decidedCards.filter { $0 != cardID }
        if isDecided {
            list.append(cardID)
            deck.decidedAt = Date()
            deck.decidedBy = name
        }
        deck.decided = list
        if deck.decidedAt == nil { deck.decidedAt = Date() }
        // Deciding in a round makes that card the round's winner in the history.
        if isDecided, let round = deck.activeRound, deck.roundCards?.contains(cardID) == true {
            remember(card, round: round, in: &deck)
        }
        decks[deck.id] = deck
        enqueueSave(deck.id, in: group)
        scheduleSave()
    }

    /// Saves where the spinner landed, so everyone sees the same winner. Nil clears it.
    func setSpin(_ cardID: String?, deck deckID: String) {
        guard var deck = decks[deckID], let group = groups[deck.groupID] else { return }
        deck.spinCardID = cardID ?? ""
        deck.spinAt = Date()
        decks[deckID] = deck
        enqueueSave(deckID, in: group)
        scheduleSave()
    }

    // MARK: People and votes

    /// Adds a name to the group, or returns the person who already has it.
    func addPlayer(named raw: String, to groupID: String) -> Player? {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !name.isEmpty, let group = groups[groupID] else { return nil }
        let existing = players(in: groupID)
        if let same = existing.first(where: { $0.name.lowercased() == name.lowercased() }) { return same }
        let player = Player(groupID: groupID, name: name, color: Player.nextColor(after: existing), createdAt: Date())
        players[player.id] = player
        enqueueSave(player.id, in: group)
        scheduleSave()
        return player
    }

    /// Sets or clears one person's vote on a card, in vetting or in a round.
    func setVote(_ vote: Vote?, card cardID: String, player playerID: String, round: String? = nil) {
        guard let card = cards[cardID], let group = groups[card.groupID] else { return }
        let id = Pick.id(cardID: cardID, playerID: playerID, roundID: round)
        if let vote {
            var pick = picks[id] ?? Pick(groupID: group.id, deckID: card.deckID, cardID: cardID, playerID: playerID,
                                         vote: vote, updatedAt: Date(), roundID: round)
            pick.vote = vote
            pick.updatedAt = Date()
            picks[id] = pick
            enqueueSave(id, in: group)
        } else if picks[id] != nil {
            picks[id] = nil
            enqueueDelete(id, in: group)
        }
        scheduleSave()
    }

    /// "Clear my swipes" for one deck's vetting. Round votes are left alone.
    func clearVotes(deck deckID: String, player playerID: String) {
        for pick in picks.values where pick.deckID == deckID && pick.playerID == playerID && pick.roundID == nil {
            setVote(nil, card: pick.cardID, player: playerID)
        }
    }

    // MARK: Rounds

    /// Starts a round, or starts a new one over the round running now. A new
    /// round clears everyone's round votes, the decided list and the spin, after
    /// saving the old round's winner. Vetting votes are never touched.
    @discardableResult
    func startRound(deck deckID: String, question: String, chain: [String]? = nil, filter: [String]? = nil) -> Rounds.Plan? {
        guard var deck = decks[deckID], let group = groups[deck.groupID] else { return nil }
        closeRound(&deck)
        let filter = filter ?? deck.roundFilter ?? []
        let plan = Rounds.plan(vetting: state(of: deckID, me: nil), filter: filter)
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        deck.roundID = makeID()
        deck.roundQuestion = String((trimmed.isEmpty ? Rounds.defaultQuestion : trimmed).prefix(80))
        deck.roundStartedAt = Date()
        deck.roundCards = plan.cards.map(\.id)
        deck.roundFilter = filter
        deck.roundChain = chain ?? deck.roundChain ?? []
        decks[deckID] = deck
        enqueueSave(deckID, in: group)
        scheduleSave()
        return plan
    }

    /// Ends the round running now, saving its winner. The deck goes back to vetting.
    func endRound(deck deckID: String) {
        guard var deck = decks[deckID], let group = groups[deck.groupID], deck.activeRound != nil else { return }
        closeRound(&deck)
        deck.roundID = ""
        deck.roundCards = []
        deck.roundChain = []
        deck.roundFilter = []
        decks[deckID] = deck
        enqueueSave(deckID, in: group)
        scheduleSave()
    }

    /// Saves the round's winner (if it has one), then clears its votes, the
    /// decided list and the spin, ready for whatever comes next.
    private func closeRound(_ deck: inout Deck) {
        guard let round = deck.activeRound, let group = groups[deck.groupID] else { return }
        if let state = roundState(of: deck.id, me: nil),
           let winner = Rounds.winner(of: state, decided: deck.decidedCards, spin: deck.spinCardID) {
            remember(winner, round: round, in: &deck)
        }
        for pick in picks.values where pick.deckID == deck.id && pick.roundID != nil {
            picks[pick.id] = nil
            enqueueDelete(pick.id, in: group)
        }
        if deck.decided != nil { deck.decided = [] }
        if deck.spinCardID != nil { deck.spinCardID = "" }
    }

    private func remember(_ card: Card, round: String, in deck: inout Deck) {
        let result = RoundResult(roundID: round, question: deck.roundQuestion ?? Rounds.defaultQuestion,
                                 cardID: card.id, title: card.title, at: Date())
        deck.roundHistory = Rounds.record(result, in: deck.roundHistory ?? [])
    }

    /// The next deck in a chain, narrowed to this round's winner. Returns its ID.
    func startNextInChain(from deckID: String, winner cardID: String) -> String? {
        guard let deck = decks[deckID], let winner = cards[cardID],
              let nextID = deck.roundChain?.first(where: { decks[$0] != nil }) else { return nil }
        let rest = Array((deck.roundChain ?? []).drop { $0 != nextID }.dropFirst())
        startRound(deck: nextID, question: deck.roundQuestion ?? Rounds.defaultQuestion, chain: rest,
                   filter: (deck.roundFilter ?? []) + [winner.title])
        return nextID
    }

    /// "Never, for good": takes a card out of every round and stack, for
    /// everyone, until someone brings it back. Its votes are kept.
    func retire(card cardID: String, by name: String?) {
        guard var card = cards[cardID], let group = groups[card.groupID] else { return }
        card.retiredAt = Date()
        card.retiredBy = name ?? ""
        cards[cardID] = card
        enqueueSave(cardID, in: group)
        scheduleSave()
    }

    func bringBack(card cardID: String) {
        guard var card = cards[cardID], let group = groups[card.groupID] else { return }
        card.retiredAt = nil
        if card.retiredBy == nil { card.retiredBy = "" }
        cards[cardID] = card
        enqueueSave(cardID, in: group)
        scheduleSave()
    }

    /// Sets when an event card happens, for everyone. Nil takes the time off.
    func setTime(_ date: Date?, card cardID: String) {
        guard var card = cards[cardID], let group = groups[card.groupID], card.startsAt != date else { return }
        if date == nil && card.startsAt != nil { card.timeCleared = true }
        card.startsAt = date
        cards[cardID] = card
        enqueueSave(cardID, in: group)
        scheduleSave()
    }

    // MARK: Sharing

    enum ShareError: LocalizedError {
        case notOwner, notSignedIn, failed

        var errorDescription: String? {
            switch self {
            case .notOwner: return "Only the person who made this group can invite people."
            case .notSignedIn: return "Sign in to iCloud in Settings to invite people."
            case .failed: return "Couldn’t set up sharing. Check your connection and try again."
            }
        }
    }

    /// The group's share, created the first time someone invites people.
    func share(for groupID: String) async throws -> CKShare {
        guard let group = groups[groupID], group.isOwned else { throw ShareError.notOwner }
        await refreshAccountStatus()
        guard isSignedIn else { throw ShareError.notSignedIn }
        let zone = zoneID(for: group)
        let database = container.privateCloudDatabase
        // The zone and its records have to be on the server before they can be shared.
        try await privateEngine?.sendChanges()
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        if let existing = try? await database.record(for: shareID) as? CKShare {
            return existing
        }
        let share = CKShare(recordZoneID: zone)
        share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
        share.publicPermission = .none
        let result = try await database.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[shareID]?.get() as? CKShare else { throw ShareError.failed }
        groups[groupID]?.isShared = true
        scheduleSave()
        return saved
    }

    /// Lets anyone with the group's link (or its QR code) join and swipe, or
    /// goes back to invited people only. Returns the link.
    func setOpenToAnyone(_ open: Bool, groupID: String) async throws -> URL {
        let share = try await share(for: groupID)
        let wanted: CKShare.ParticipantPermission = open ? .readWrite : .none
        var current = share
        if share.publicPermission != wanted {
            share.publicPermission = wanted
            let result = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
            guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else { throw ShareError.failed }
            current = saved
        }
        guard let url = current.url else { throw ShareError.failed }
        groups[groupID]?.openToAnyone = open
        scheduleSave()
        return url
    }

    /// Joins a group from an iCloud invitation link.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
                operation.acceptSharesResultBlock = { result in continuation.resume(with: result) }
                container.add(operation)
            }
            let zone = metadata.share.recordID.zoneID
            if groups[zone.zoneName] == nil {
                var group = SwipeGroup(id: zone.zoneName, ownerName: zone.ownerName,
                                       name: metadata.share[CKShare.SystemFieldKey.title] as? String ?? "Shared decks",
                                       isOwned: false, createdAt: Date())
                group.isShared = true
                groups[zone.zoneName] = group
            }
            joinedGroupID = zone.zoneName
            scheduleSave()
            try? await sharedEngine?.fetchChanges()
        } catch {
            notice = "Couldn’t join that group: \(error.localizedDescription)"
        }
    }

    // MARK: Syncing

    func refresh() async {
        guard !Screenshots.isActive else { return }
        await refreshAccountStatus()
        try? await privateEngine?.fetchChanges()
        try? await sharedEngine?.fetchChanges()
        try? await privateEngine?.sendChanges()
        try? await sharedEngine?.sendChanges()
    }

    func refreshAccountStatus() async {
        guard !Screenshots.isActive else { return }
        accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
    }

    private func startEngines() {
        privateEngine = CKSyncEngine(CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                               stateSerialization: privateState, delegate: self))
        sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(database: container.sharedCloudDatabase,
                                                              stateSerialization: sharedState, delegate: self))
    }

    private func zoneID(for group: SwipeGroup) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: group.id, ownerName: group.ownerName)
    }

    private func engine(for group: SwipeGroup) -> CKSyncEngine? {
        group.isOwned ? privateEngine : sharedEngine
    }

    private func enqueueSave(_ recordName: String, in group: SwipeGroup) {
        let id = CKRecord.ID(recordName: recordName, zoneID: zoneID(for: group))
        engine(for: group)?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    private func enqueueDelete(_ recordName: String, in group: SwipeGroup) {
        let id = CKRecord.ID(recordName: recordName, zoneID: zoneID(for: group))
        engine(for: group)?.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let isPrivate = syncEngine === privateEngine
        switch event {
        case .stateUpdate(let update):
            if isPrivate { privateState = update.stateSerialization } else { sharedState = update.stateSerialization }
            scheduleSave()

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                await refreshAccountStatus()
            case .signOut, .switchAccounts:
                // Someone else's iCloud: don't keep the last person's decks on the phone.
                wipeLocalData()
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions {
                let zone = deletion.zoneID
                if isPrivate && deletion.reason == .encryptedDataReset {
                    reupload(zone.zoneName)
                } else {
                    dropGroup(zone.zoneName)
                }
            }
            if !isPrivate {
                for modification in changes.modifications where groups[modification.zoneID.zoneName] == nil {
                    var group = SwipeGroup(id: modification.zoneID.zoneName, ownerName: modification.zoneID.ownerName,
                                           name: "Shared decks", isOwned: false, createdAt: Date())
                    group.isShared = true
                    groups[group.id] = group
                }
            }
            scheduleSave()

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                apply(modification.record)
            }
            for deletion in changes.deletions {
                removeRecord(deletion.recordID, type: deletion.recordType)
            }
            scheduleSave()

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                storeSystemFields(of: record)
            }
            for failure in sent.failedRecordSaves {
                handleFailedSave(failure.record, error: failure.error, engine: syncEngine)
            }
            scheduleSave()

        case .willFetchChanges, .willSendChanges:
            isSyncing = true

        case .didFetchChanges, .didSendChanges:
            isSyncing = false

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        var records: [CKRecord.ID: CKRecord] = [:]
        var gone: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in changes {
            guard case .saveRecord(let id) = change else { continue }
            if let record = record(for: id) {
                records[id] = record
            } else {
                // Deleted here before it was ever sent.
                gone.append(change)
            }
        }
        if !gone.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: gone)
        }
        let sendable = changes.filter { !gone.contains($0) }
        guard !sendable.isEmpty else { return nil }
        let batch = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: sendable) { id in batch[id] }
    }

    // MARK: Records in and out

    private func record(for id: CKRecord.ID) -> CKRecord? {
        let zone = id.zoneID
        let name = id.recordName
        if name == Records.groupRecordName, let group = groups[zone.zoneName] {
            return Records.record(group, zoneID: zone)
        }
        if let deck = decks[name] { return Records.record(deck, zoneID: zone) }
        if let card = cards[name] { return Records.record(card, zoneID: zone) }
        if let player = players[name] { return Records.record(player, zoneID: zone) }
        if let pick = picks[name] { return Records.record(pick, zoneID: zone) }
        if let answer = answers[name] { return Records.record(answer, zoneID: zone) }
        return nil
    }

    private func apply(_ record: CKRecord) {
        let zone = record.recordID.zoneID
        let groupID = zone.zoneName
        if let share = record as? CKShare {
            applyShare(share, groupID: groupID)
            return
        }
        switch record.recordType {
        case Records.Kind.group:
            var group = groups[groupID] ?? SwipeGroup(id: groupID, ownerName: zone.ownerName, name: "Shared decks",
                                                      isOwned: zone.ownerName == CKCurrentUserDefaultName, createdAt: Date())
            Records.read(record, into: &group)
            groups[groupID] = group
        case Records.Kind.deck:
            decks[record.recordID.recordName] = Records.deck(from: record, groupID: groupID)
        case Records.Kind.card:
            cards[record.recordID.recordName] = Records.card(from: record, groupID: groupID)
        case Records.Kind.player:
            players[record.recordID.recordName] = Records.player(from: record, groupID: groupID)
        case Records.Kind.pick:
            if let pick = Records.pick(from: record, groupID: groupID) { picks[pick.id] = pick }
        case Records.Kind.answer:
            if let answer = Records.answers(from: record, groupID: groupID) { answers[answer.id] = answer }
        default:
            break
        }
    }

    private func applyShare(_ share: CKShare, groupID: String) {
        guard var group = groups[groupID] else { return }
        group.isShared = true
        group.openToAnyone = share.publicPermission != .none
        group.participants = share.participants
            .filter { $0.role != .owner && $0.acceptanceStatus == .accepted }
            .compactMap { participant in
                participant.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            }
        if !group.isOwned {
            group.readOnly = share.currentUserParticipant?.permission == .readOnly
            if let title = share[CKShare.SystemFieldKey.title] as? String, group.name == "Shared decks" {
                group.name = title
            }
        }
        groups[groupID] = group
    }

    private func removeRecord(_ id: CKRecord.ID, type: CKRecord.RecordType) {
        let name = id.recordName
        switch type {
        case CKRecord.SystemType.share:
            groups[id.zoneID.zoneName]?.isShared = false
            groups[id.zoneID.zoneName]?.participants = []
        case Records.Kind.deck:
            removeDeckLocally(name)
        case Records.Kind.card:
            cards[name] = nil
            picks = picks.filter { $0.value.cardID != name }
        case Records.Kind.player:
            players[name] = nil
        case Records.Kind.pick:
            picks[name] = nil
        case Records.Kind.answer:
            answers[name] = nil
        default:
            break
        }
    }

    private func storeSystemFields(of record: CKRecord) {
        let data = record.archivedSystemFields
        let name = record.recordID.recordName
        if name == Records.groupRecordName {
            groups[record.recordID.zoneID.zoneName]?.systemFields = data
        } else if decks[name] != nil {
            decks[name]?.systemFields = data
        } else if cards[name] != nil {
            cards[name]?.systemFields = data
        } else if players[name] != nil {
            players[name]?.systemFields = data
        } else if picks[name] != nil {
            picks[name]?.systemFields = data
        } else if answers[name] != nil {
            answers[name]?.systemFields = data
        }
    }

    private func clearSystemFields(_ id: CKRecord.ID) {
        let name = id.recordName
        if name == Records.groupRecordName { groups[id.zoneID.zoneName]?.systemFields = nil }
        decks[name]?.systemFields = nil
        cards[name]?.systemFields = nil
        players[name]?.systemFields = nil
        picks[name]?.systemFields = nil
        answers[name]?.systemFields = nil
    }

    private func handleFailedSave(_ record: CKRecord, error: CKError, engine: CKSyncEngine) {
        let id = record.recordID
        switch error.code {
        case .serverRecordChanged:
            // Someone else saved first. Take their change tag and save ours over it.
            if let server = error.serverRecord { storeSystemFields(of: server) }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .zoneNotFound:
            if engine === privateEngine {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                clearSystemFields(id)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            } else {
                // The owner stopped sharing or deleted the group.
                dropGroup(id.zoneID.zoneName)
            }
        case .unknownItem:
            clearSystemFields(id)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .permissionFailure:
            markReadOnly(id.zoneID.zoneName)
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
             .operationCancelled, .requestRateLimited:
            break // The engine retries these on its own.
        case .quotaExceeded:
            notice = "Your iCloud storage is full, so changes aren’t syncing."
        default:
            notice = "A change didn’t sync: \(error.localizedDescription)"
        }
    }

    private func markReadOnly(_ groupID: String) {
        guard groups[groupID]?.readOnly == false else { return }
        groups[groupID]?.readOnly = true
        notice = "You can look around, but changes won’t save. Ask the person who invited you to let you make changes."
    }

    private func removeDeckLocally(_ id: String) {
        decks[id] = nil
        let cardIDs = Set(cards.values.filter { $0.deckID == id }.map(\.id))
        cards = cards.filter { !cardIDs.contains($0.key) }
        picks = picks.filter { $0.value.deckID != id }
        answers = answers.filter { $0.value.deckID != id }
    }

    private func dropGroup(_ id: String) {
        groups[id] = nil
        let deckIDs = decks.values.filter { $0.groupID == id }.map(\.id)
        for deckID in deckIDs { removeDeckLocally(deckID) }
        players = players.filter { $0.value.groupID != id }
    }

    /// After an iCloud data reset, send a group's records again from this phone.
    private func reupload(_ groupID: String) {
        guard var group = groups[groupID] else { return }
        group.systemFields = nil
        groups[groupID] = group
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID(for: group)))])
        var names = [Records.groupRecordName]
        for (id, var deck) in decks where deck.groupID == groupID { deck.systemFields = nil; decks[id] = deck; names.append(id) }
        for (id, var card) in cards where card.groupID == groupID { card.systemFields = nil; cards[id] = card; names.append(id) }
        for (id, var player) in players where player.groupID == groupID { player.systemFields = nil; players[id] = player; names.append(id) }
        for (id, var pick) in picks where pick.groupID == groupID { pick.systemFields = nil; picks[id] = pick; names.append(id) }
        for (id, var answer) in answers where answer.groupID == groupID {
            answer.systemFields = nil
            answers[id] = answer
            names.append(id)
        }
        for name in names { enqueueSave(name, in: group) }
    }

    private func wipeLocalData() {
        groups = [:]
        decks = [:]
        cards = [:]
        players = [:]
        picks = [:]
        answers = [:]
        privateState = nil
        sharedState = nil
        startEngines()
        scheduleSave()
    }

    // MARK: Local file

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        groups = Dictionary(snapshot.groups.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        decks = Dictionary(snapshot.decks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        cards = Dictionary(snapshot.cards.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        players = Dictionary(snapshot.players.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        picks = Dictionary(snapshot.picks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        answers = Dictionary((snapshot.answers ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        privateState = snapshot.privateState
        sharedState = snapshot.sharedState
    }

    /// Writes the file half a second after the last change.
    private func scheduleSave() {
        guard !Screenshots.isActive else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    func writeNow() {
        guard !Screenshots.isActive else { return }
        let snapshot = Snapshot(groups: Array(groups.values), decks: Array(decks.values), cards: Array(cards.values),
                                players: Array(players.values), picks: Array(picks.values),
                                answers: Array(answers.values),
                                privateState: privateState, sharedState: sharedState)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Screenshot sample data

    private func loadScreenshotData() {
        let now = Date()
        var group = SwipeGroup(id: Screenshots.groupID, ownerName: CKCurrentUserDefaultName, name: "Sam & Alex",
                               isOwned: true, createdAt: now.addingTimeInterval(-30 * 86_400))
        group.isShared = true
        group.participants = ["Alex"]
        groups = [group.id: group]
        let sam = Player(id: Screenshots.meID, groupID: group.id, name: "Sam", color: 2, createdAt: now.addingTimeInterval(-900))
        let alex = Player(id: "alex", groupID: group.id, name: "Alex", color: 3, createdAt: now.addingTimeInterval(-800))
        players = [sam.id: sam, alex.id: alex]
        accountStatus = .available

        for sample in Screenshots.decks {
            let deck = Deck(id: sample.id, groupID: group.id, title: sample.title, kind: sample.kind, blurb: sample.blurb,
                            createdAt: now.addingTimeInterval(sample.age))
            decks[deck.id] = deck
            for (index, item) in sample.cards.enumerated() {
                let card = Card(id: item.id, groupID: group.id, deckID: deck.id,
                                draft: CardDraft(title: item.title, subtitle: item.subtitle, details: item.details, tags: item.tags),
                                order: Double(index), createdAt: deck.createdAt)
                cards[card.id] = card
                for (playerID, vote) in [(alex.id, item.alex), (sam.id, item.sam)] {
                    guard let vote else { continue }
                    let pick = Pick(groupID: group.id, deckID: deck.id, cardID: card.id, playerID: playerID, vote: vote, updatedAt: now)
                    picks[pick.id] = pick
                }
            }
        }

        if Screenshots.screen == "starterswipe" {
            let deck = Deck(id: Screenshots.starterDeckID, groupID: group.id, title: Starter.dates.title, kind: Starter.dates.kind,
                            blurb: Starter.dates.blurb, createdAt: now)
            decks[deck.id] = deck
            for (index, starter) in Starter.dates.cards.filter({ $0.hasPhoto }).prefix(6).enumerated() {
                let card = Card(id: "indy-" + starter.id, groupID: group.id, deckID: deck.id, draft: starter.draft,
                                order: Double(index), createdAt: now)
                cards[card.id] = card
            }
        }

        // The trip deck asks the Trip questions. Alex confirmed theirs and
        // filled some in for Sam, who hasn't confirmed yet.
        if var trip = decks[Screenshots.tripDeckID] {
            trip.questions = Screenshots.tripQuestions
            decks[trip.id] = trip
            let sample = Screenshots.tripAnswers(now: now)
            let alexAnswers = FormAnswers(groupID: group.id, deckID: trip.id, playerID: alex.id, values: sample.alex,
                                          filledBy: alex.id, confirmedAt: now, updatedAt: now)
            let samAnswers = FormAnswers(groupID: group.id, deckID: trip.id, playerID: sam.id, values: sample.forSam,
                                         filledBy: alex.id, updatedAt: now)
            answers = [alexAnswers.id: alexAnswers, samAnswers.id: samAnswers]
        }

        // The dinners deck is vetted and has tonight's round going, with two past winners.
        guard var dinners = decks[Screenshots.dinnerDeckID] else { return }
        let plan = Rounds.plan(vetting: state(of: dinners.id, me: nil))
        dinners.roundID = Screenshots.roundID
        dinners.roundQuestion = "What sounds good tonight?"
        dinners.roundStartedAt = now.addingTimeInterval(-1_800)
        dinners.roundCards = plan.cards.map(\.id)
        dinners.roundHistory = [
            RoundResult(roundID: "r-mon", question: "Monday dinner?", cardID: "card-fajitas", title: "Sheet-pan fajitas",
                        at: now.addingTimeInterval(-2 * 86_400)),
            RoundResult(roundID: "r-wed", question: "What sounds good tonight?", cardID: "card-pizza", title: "Homemade pizza night",
                        at: now.addingTimeInterval(-86_400)),
        ]
        decks[dinners.id] = dinners
        for (cardID, vote) in Screenshots.alexRound {
            let pick = Pick(groupID: group.id, deckID: dinners.id, cardID: cardID, playerID: alex.id, vote: vote,
                            updatedAt: now, roundID: Screenshots.roundID)
            picks[pick.id] = pick
        }
        if Screenshots.screen == "roundresults" {
            for (cardID, vote) in Screenshots.samRound {
                let pick = Pick(groupID: group.id, deckID: dinners.id, cardID: cardID, playerID: sam.id, vote: vote,
                                updatedAt: now, roundID: Screenshots.roundID)
                picks[pick.id] = pick
            }
        }
    }
}
