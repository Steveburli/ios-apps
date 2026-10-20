import CloudKit
import MutualKit

/// How each model maps to a CloudKit record. Every group is a zone holding a
/// "Group" record plus its decks, cards, players and picks.
///
/// Field names are part of the production schema once it's deployed, so
/// never rename one. Add new fields instead.
enum Records {
    static let groupRecordName = "group"

    enum Kind {
        static let group = "Group"
        static let deck = "Deck"
        static let card = "Card"
        static let player = "Player"
        static let pick = "Pick"
    }

    /// Starts from the last record the server sent, so the save carries its
    /// change tag. Otherwise it's a new record.
    private static func base(_ type: String, name: String, zoneID: CKRecordZone.ID, systemFields: Data?) -> CKRecord {
        if let data = systemFields, let record = CKRecord.fromArchivedSystemFields(data),
           record.recordID.recordName == name, record.recordID.zoneID == zoneID {
            return record
        }
        return CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
    }

    // MARK: Writing

    static func record(_ group: SwipeGroup, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = base(Kind.group, name: groupRecordName, zoneID: zoneID, systemFields: group.systemFields)
        record["name"] = group.name
        record["createdAt"] = group.createdAt
        return record
    }

    static func record(_ deck: Deck, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = base(Kind.deck, name: deck.id, zoneID: zoneID, systemFields: deck.systemFields)
        record["title"] = deck.title
        record["kind"] = deck.kind.rawValue
        record["blurb"] = deck.blurb
        record["createdAt"] = deck.createdAt
        return record
    }

    static func record(_ card: Card, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = base(Kind.card, name: card.id, zoneID: zoneID, systemFields: card.systemFields)
        // Deleting a deck deletes its cards, and their picks, on the server.
        record["deck"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: card.deckID, zoneID: zoneID), action: .deleteSelf)
        record["deckID"] = card.deckID
        record["title"] = card.title
        record["subtitle"] = card.subtitle
        record["details"] = card.details
        record["tags"] = card.tags
        record["link"] = card.link
        record["order"] = card.order
        record["createdAt"] = card.createdAt
        return record
    }

    static func record(_ player: Player, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = base(Kind.player, name: player.id, zoneID: zoneID, systemFields: player.systemFields)
        record["name"] = player.name
        record["color"] = Int64(player.color)
        record["createdAt"] = player.createdAt
        return record
    }

    static func record(_ pick: Pick, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = base(Kind.pick, name: pick.id, zoneID: zoneID, systemFields: pick.systemFields)
        // Picks hang off their card, not the deck, to stay well under
        // CloudKit's limit on references to one record.
        record["card"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: pick.cardID, zoneID: zoneID), action: .deleteSelf)
        record["deckID"] = pick.deckID
        record["cardID"] = pick.cardID
        record["playerID"] = pick.playerID
        record["vote"] = pick.vote.rawValue
        record["updatedAt"] = pick.updatedAt
        return record
    }

    // MARK: Reading

    private static func string(_ record: CKRecord, _ key: String) -> String {
        record[key] as? String ?? ""
    }

    private static func date(_ record: CKRecord, _ key: String) -> Date {
        record[key] as? Date ?? record.creationDate ?? Date()
    }

    static func read(_ record: CKRecord, into group: inout SwipeGroup) {
        let name = string(record, "name")
        if !name.isEmpty { group.name = name }
        group.createdAt = date(record, "createdAt")
        group.systemFields = record.archivedSystemFields
    }

    static func deck(from record: CKRecord, groupID: String) -> Deck {
        var deck = Deck(id: record.recordID.recordName, groupID: groupID, title: string(record, "title"),
                        kind: DeckKind(rawValue: string(record, "kind")) ?? .other, blurb: string(record, "blurb"),
                        createdAt: date(record, "createdAt"))
        deck.systemFields = record.archivedSystemFields
        return deck
    }

    static func card(from record: CKRecord, groupID: String) -> Card {
        let draft = CardDraft(title: string(record, "title"), subtitle: string(record, "subtitle"),
                              details: string(record, "details"), link: string(record, "link"),
                              tags: record["tags"] as? [String] ?? [])
        var card = Card(id: record.recordID.recordName, groupID: groupID, deckID: string(record, "deckID"), draft: draft,
                        order: record["order"] as? Double ?? 0, createdAt: date(record, "createdAt"))
        card.systemFields = record.archivedSystemFields
        return card
    }

    static func player(from record: CKRecord, groupID: String) -> Player {
        let color = (record["color"] as? Int64).map { Int($0) } ?? 0
        var player = Player(id: record.recordID.recordName, groupID: groupID, name: string(record, "name"),
                            color: max(0, min(7, color)), createdAt: date(record, "createdAt"))
        player.systemFields = record.archivedSystemFields
        return player
    }

    static func pick(from record: CKRecord, groupID: String) -> Pick? {
        guard let vote = Vote(rawValue: string(record, "vote")) else { return nil }
        var pick = Pick(groupID: groupID, deckID: string(record, "deckID"), cardID: string(record, "cardID"),
                        playerID: string(record, "playerID"), vote: vote, updatedAt: date(record, "updatedAt"))
        pick.id = record.recordID.recordName
        pick.systemFields = record.archivedSystemFields
        return pick
    }
}

extension CKRecord {
    /// The record's server metadata (ID, change tag), without its fields.
    var archivedSystemFields: Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func fromArchivedSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
