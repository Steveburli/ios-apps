import CloudKit
import DoThisNowKit

/// How trips map to CloudKit records. Every trip is a zone holding a "Trip"
/// record plus one "Stop" record per place.
///
/// Each record keeps its model as JSON in one `payload` field, so new model
/// fields never need a schema change. Field names are part of the production
/// schema once it's deployed, so never rename one.
enum TripRecords {
    static let tripRecordName = "trip"

    enum Kind {
        static let trip = "Trip"
        static let stop = "Stop"
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

    static func record(_ trip: Trip, zoneID: CKRecordZone.ID, systemFields: Data?) -> CKRecord {
        let record = base(Kind.trip, name: tripRecordName, zoneID: zoneID, systemFields: systemFields)
        record["payload"] = json(trip)
        return record
    }

    static func record(_ stop: TripStop, zoneID: CKRecordZone.ID, systemFields: Data?) -> CKRecord {
        let record = base(Kind.stop, name: stop.id, zoneID: zoneID, systemFields: systemFields)
        record["payload"] = json(stop)
        return record
    }

    static func trip(from record: CKRecord) -> Trip? {
        decode(Trip.self, record)
    }

    static func stop(from record: CKRecord) -> TripStop? {
        decode(TripStop.self, record)
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ record: CKRecord) -> T? {
        guard let text = record["payload"] as? String else { return nil }
        return try? JSONDecoder().decode(type, from: Data(text.utf8))
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
