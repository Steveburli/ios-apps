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
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    private(set) var isSyncing = false
    /// A message for the person, shown once as a toast.
    var notice: String?
    /// The group just joined from an invitation, so the UI can switch to it.
    var joinedGroupID: String?

    @ObservationIgnored let container: CKContainer
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
        var privateState: CKSyncEngine.State.Serialization?
        var sharedState: CKSyncEngine.State.Serialization?
    }

    private init() {
        container = CKContainer(identifier: Self.containerID)
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("mutual.json")
        load()
        startEngines()
        Task { await refreshAccountStatus() }
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

    func cards(in deckID: String) -> [Card] {
        cards.values.filter { $0.deckID == deckID }.inSwipeOrder()
    }

    func players(in groupID: String) -> [Player] {
        players.values.filter { $0.groupID == groupID }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    func state(of deckID: String, me: String?) -> DeckState {
        let deck = decks[deckID]
        let deckPicks = picks.values.filter { $0.deckID == deckID }
        return DeckState(cards: cards(in: deckID), players: deck.map { players(in: $0.groupID) } ?? [],
                         picks: Array(deckPicks), me: me)
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
        guard let deck = decks[deckID], let group = groups[deck.groupID] else { return 0 }
        let base = Date().timeIntervalSince1970 * 1000
        var added = 0
        for (i, draft) in drafts.enumerated() {
            guard let clean = CardText.clean(draft) else { continue }
            let card = Card(groupID: group.id, deckID: deckID, draft: clean, order: base + Double(i), createdAt: Date())
            cards[card.id] = card
            enqueueSave(card.id, in: group)
            added += 1
        }
        scheduleSave()
        return added
    }

    func deleteCard(_ id: String) {
        guard let card = cards[id], let group = groups[card.groupID] else { return }
        enqueueDelete(id, in: group)
        cards[id] = nil
        picks = picks.filter { $0.value.cardID != id }
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

    /// Sets or clears one person's vote on a card.
    func setVote(_ vote: Vote?, card cardID: String, player playerID: String) {
        guard let card = cards[cardID], let group = groups[card.groupID] else { return }
        let id = Pick.id(cardID: cardID, playerID: playerID)
        if let vote {
            var pick = picks[id] ?? Pick(groupID: group.id, deckID: card.deckID, cardID: cardID, playerID: playerID,
                                         vote: vote, updatedAt: Date())
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

    /// "Clear my swipes" for one deck.
    func clearVotes(deck deckID: String, player playerID: String) {
        for pick in picks.values where pick.deckID == deckID && pick.playerID == playerID {
            setVote(nil, card: pick.cardID, player: playerID)
        }
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
        await refreshAccountStatus()
        try? await privateEngine?.fetchChanges()
        try? await sharedEngine?.fetchChanges()
        try? await privateEngine?.sendChanges()
        try? await sharedEngine?.sendChanges()
    }

    func refreshAccountStatus() async {
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
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: sendable) { id in records[id] }
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
        default:
            break
        }
    }

    private func applyShare(_ share: CKShare, groupID: String) {
        guard var group = groups[groupID] else { return }
        group.isShared = true
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
        }
    }

    private func clearSystemFields(_ id: CKRecord.ID) {
        let name = id.recordName
        if name == Records.groupRecordName { groups[id.zoneID.zoneName]?.systemFields = nil }
        decks[name]?.systemFields = nil
        cards[name]?.systemFields = nil
        players[name]?.systemFields = nil
        picks[name]?.systemFields = nil
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
        for name in names { enqueueSave(name, in: group) }
    }

    private func wipeLocalData() {
        groups = [:]
        decks = [:]
        cards = [:]
        players = [:]
        picks = [:]
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
        privateState = snapshot.privateState
        sharedState = snapshot.sharedState
    }

    /// Writes the file half a second after the last change.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    func writeNow() {
        let snapshot = Snapshot(groups: Array(groups.values), decks: Array(decks.values), cards: Array(cards.values),
                                players: Array(players.values), picks: Array(picks.values),
                                privateState: privateState, sharedState: sharedState)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
