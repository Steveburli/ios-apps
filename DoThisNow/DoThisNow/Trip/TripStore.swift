import Foundation
import CloudKit
import MapKit
import Observation
import DoThisNowKit

/// Trips and their stops, kept in a local file and synced with iCloud so a
/// trip can be shared: each trip is a zone holding one "Trip" record and a
/// "Stop" record per place. Two CKSyncEngines run, one for trips you made
/// (your private database) and one for trips shared with you.
///
/// iCloud is only touched once you have a trip, so people who never plan one
/// never see it. The UI reads and writes here and never waits on the network.
@Observable
@MainActor
final class TripStore: CKSyncEngineDelegate {
    static let shared = TripStore()
    static let containerID = "iCloud.com.steveburlison.dothisnow"

    struct TripEntry: Codable {
        var trip: Trip
        var ownerName: String
        var isOwned: Bool
        var isShared = false
        var participants: [String] = []
        var readOnly = false
        var systemFields: Data?
    }

    struct StopEntry: Codable {
        var stop: TripStop
        var systemFields: Data?
    }

    private(set) var trips: [String: TripEntry] = [:]
    private(set) var stops: [String: StopEntry] = [:]
    /// Travel times from Apple Maps by `Leg.key`. Kept on this phone only.
    private(set) var legs: [String: Leg] = [:]
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    var selectedTripID: String? {
        didSet { if !Screenshots.isActive { UserDefaults.standard.set(selectedTripID, forKey: "selectedTrip") } }
    }
    /// A message for the person, shown once as a toast.
    var notice: String?
    /// Goes up when a trip should be shown, like after joining one from an invitation.
    private(set) var openRequests = 0

    @ObservationIgnored private var cachedContainer: CKContainer?
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    @ObservationIgnored private var privateState: CKSyncEngine.State.Serialization?
    @ObservationIgnored private var sharedState: CKSyncEngine.State.Serialization?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var asking: Set<String> = []

    private struct Snapshot: Codable {
        var trips: [TripEntry] = []
        var stops: [StopEntry] = []
        var legs: [String: Leg] = [:]
        var privateState: CKSyncEngine.State.Serialization?
        var sharedState: CKSyncEngine.State.Serialization?
    }

    private init() {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("trips.json")
        if Screenshots.isActive {
            // Unsigned screenshot builds have no iCloud access, so use the example trip instead.
            loadScreenshotData()
            return
        }
        load()
        selectedTripID = UserDefaults.standard.string(forKey: "selectedTrip")
        if trips.values.contains(where: { !$0.trip.isExample }) {
            startEngines()
        }
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

    /// Soonest first, then trips shared with you.
    var sortedTrips: [TripEntry] {
        trips.values.sorted { a, b in
            if a.trip.day != b.trip.day { return a.trip.day < b.trip.day }
            return (a.trip.createdAt, a.trip.id) < (b.trip.createdAt, b.trip.id)
        }
    }

    var selected: TripEntry? {
        if let selectedTripID, let entry = trips[selectedTripID] { return entry }
        return sortedTrips.first
    }

    func planner(for tripID: String) -> TripPlanner? {
        guard let entry = trips[tripID] else { return nil }
        return TripPlanner(trip: entry.trip, stops: stops.values.map(\.stop).filter { $0.tripID == tripID }, legs: legs)
    }

    func stop(_ id: String) -> TripStop? {
        stops[id]?.stop
    }

    func canWrite(_ tripID: String) -> Bool {
        !(trips[tripID]?.readOnly ?? true)
    }

    // MARK: Trips

    @discardableResult
    func createTrip(name: String, day: CalendarDay, startMinute: Int) -> Trip {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trip = Trip(name: trimmed.isEmpty ? "Trip" : String(trimmed.prefix(60)), day: day, startMinute: startMinute,
                        endMinute: max(startMinute + 60, 1320))
        trips[trip.id] = TripEntry(trip: trip, ownerName: CKCurrentUserDefaultName, isOwned: true)
        selectedTripID = trip.id
        startEngines()
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID(trip.id)))])
        enqueueSave(TripRecords.tripRecordName, tripID: trip.id)
        scheduleSave()
        return trip
    }

    func addExample(on day: CalendarDay) {
        let example = TripExample.make(on: day)
        trips[example.trip.id] = TripEntry(trip: example.trip, ownerName: CKCurrentUserDefaultName, isOwned: true)
        for stop in example.stops { stops[stop.id] = StopEntry(stop: stop) }
        selectedTripID = example.trip.id
        scheduleSave()
    }

    func update(_ trip: Trip) {
        guard var entry = trips[trip.id], !entry.readOnly else { return }
        entry.trip = trip
        trips[trip.id] = entry
        enqueueSave(TripRecords.tripRecordName, tripID: trip.id)
        scheduleSave()
    }

    /// Deletes a trip you made (and stops sharing it), or leaves one shared with you.
    func removeTrip(_ id: String) {
        guard let entry = trips[id] else { return }
        if !entry.trip.isExample {
            engine(for: id)?.state.add(pendingDatabaseChanges: [.deleteZone(zoneID(id))])
        }
        dropTrip(id)
        if selectedTripID == id { selectedTripID = sortedTrips.first?.trip.id }
        scheduleSave()
    }

    // MARK: Stops

    func save(_ stop: TripStop) {
        guard canWrite(stop.tripID) else { return }
        var stop = stop
        if stops[stop.id] == nil {
            // New stops go at the end of the day or the wish list.
            let siblings = stops.values.map(\.stop).filter { $0.tripID == stop.tripID && $0.onDay == stop.onDay }
            stop.order = (siblings.map(\.order).max() ?? 0) + 1
        }
        put(stop)
        if stop.onDay { tidyFixed(stop.tripID) }
        scheduleSave()
        fetchLegs(for: stop.tripID)
    }

    func save(_ list: [TripStop]) {
        for stop in list where canWrite(stop.tripID) && stops[stop.id]?.stop != stop {
            put(stop)
        }
        scheduleSave()
        if let tripID = list.first?.tripID { fetchLegs(for: tripID) }
    }

    func deleteStop(_ id: String) {
        guard let stop = stops[id]?.stop, canWrite(stop.tripID) else { return }
        stops[id] = nil
        enqueueDelete(id, tripID: stop.tripID)
        scheduleSave()
    }

    /// Drag to reorder the day.
    func moveDay(_ tripID: String, from source: IndexSet, to destination: Int) {
        guard var day = planner(for: tripID)?.dayStops else { return }
        day.move(fromOffsets: source, toOffset: destination)
        save(TripPlanner.sortingFixed(day))
    }

    func setOnDay(_ id: String, _ onDay: Bool) {
        guard var stop = stops[id]?.stop, stop.onDay != onDay else { return }
        stop.onDay = onDay
        let siblings = stops.values.map(\.stop).filter { $0.tripID == stop.tripID && $0.onDay == onDay }
        stop.order = (siblings.map(\.order).max() ?? 0) + 1
        put(stop)
        if onDay { tidyFixed(stop.tripID) }
        scheduleSave()
        fetchLegs(for: stop.tripID)
    }

    func toggleDone(_ id: String) {
        guard var stop = stops[id]?.stop else { return }
        stop.done.toggle()
        put(stop)
        scheduleSave()
    }

    private func put(_ stop: TripStop) {
        stops[stop.id] = StopEntry(stop: stop, systemFields: stops[stop.id]?.systemFields)
        enqueueSave(stop.id, tripID: stop.tripID)
    }

    /// Keeps fixed stops in time order after a change.
    private func tidyFixed(_ tripID: String) {
        guard let day = planner(for: tripID)?.dayStops else { return }
        for stop in TripPlanner.sortingFixed(day) where stops[stop.id]?.stop != stop {
            put(stop)
        }
    }

    // MARK: Travel times

    /// Asks Apple Maps for walking and driving times between neighbors on the
    /// day, for any pair it doesn't know yet. Without a connection the
    /// straight-line estimates stay.
    func fetchLegs(for tripID: String) {
        guard !Screenshots.isActive, let day = planner(for: tripID)?.dayStops else { return }
        let pairs = zip(day, day.dropFirst()).compactMap { a, b -> (Coordinate, Coordinate)? in
            guard let from = a.coordinate, let to = b.coordinate, from != to else { return nil }
            let key = Leg.key(from: from, to: to)
            return legs[key] == nil && !asking.contains(key) ? (from, to) : nil
        }
        for (from, to) in pairs.prefix(12) {
            let key = Leg.key(from: from, to: to)
            asking.insert(key)
            Task {
                let walk = await Self.eta(from: from, to: to, by: .walking)
                let drive = await Self.eta(from: from, to: to, by: .automobile)
                asking.remove(key)
                guard walk != nil || drive != nil else { return }
                let guess = Leg.estimate(from: from, to: to)
                legs[key] = Leg(walkMinutes: walk ?? guess.walkMinutes, driveMinutes: drive ?? guess.driveMinutes,
                                isEstimate: walk == nil || drive == nil)
                scheduleSave()
            }
        }
    }

    private static func eta(from: Coordinate, to: Coordinate, by transport: MKDirectionsTransportType) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.location))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.location))
        request.transportType = transport
        guard let response = try? await MKDirections(request: request).calculateETA() else { return nil }
        return Int((response.expectedTravelTime / 60).rounded(.up))
    }

    // MARK: Sharing

    enum ShareError: LocalizedError {
        case notOwner, notSignedIn, example, failed

        var errorDescription: String? {
            switch self {
            case .notOwner: return "Only the person who made this trip can invite people."
            case .notSignedIn: return "Sign in to iCloud in Settings to share a trip."
            case .example: return "The example trip can’t be shared. Make your own trip to share it."
            case .failed: return "Couldn’t set up sharing. Check your connection and try again."
            }
        }
    }

    /// The trip's share, made the first time someone invites people.
    func share(for tripID: String) async throws -> CKShare {
        guard let entry = trips[tripID], entry.isOwned else { throw ShareError.notOwner }
        guard !entry.trip.isExample else { throw ShareError.example }
        startEngines()
        await refreshAccountStatus()
        guard isSignedIn else { throw ShareError.notSignedIn }
        let zone = zoneID(tripID)
        let database = container.privateCloudDatabase
        // The zone and its records have to be on the server before they can be shared.
        try await privateEngine?.sendChanges()
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        if let existing = try? await database.record(for: shareID) as? CKShare {
            return existing
        }
        let share = CKShare(recordZoneID: zone)
        share[CKShare.SystemFieldKey.title] = entry.trip.name as CKRecordValue
        share.publicPermission = .none
        let result = try await database.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[shareID]?.get() as? CKShare else { throw ShareError.failed }
        trips[tripID]?.isShared = true
        scheduleSave()
        return saved
    }

    /// Joins a trip from an iCloud invitation link.
    func accept(_ metadata: CKShare.Metadata) async {
        startEngines()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
                operation.acceptSharesResultBlock = { result in continuation.resume(with: result) }
                container.add(operation)
            }
            let zone = metadata.share.recordID.zoneID
            if trips[zone.zoneName] == nil {
                let name = metadata.share[CKShare.SystemFieldKey.title] as? String ?? "Shared trip"
                var entry = TripEntry(trip: Trip(id: zone.zoneName, name: name, day: CalendarDay(Date(), calendar: .current)),
                                      ownerName: zone.ownerName, isOwned: false)
                entry.isShared = true
                trips[zone.zoneName] = entry
            }
            selectedTripID = zone.zoneName
            openRequests += 1
            scheduleSave()
            try? await sharedEngine?.fetchChanges()
        } catch {
            notice = "Couldn’t open that trip: \(error.localizedDescription)"
        }
    }

    // MARK: Syncing

    func refresh() async {
        guard !Screenshots.isActive, privateEngine != nil else { return }
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
        guard !Screenshots.isActive, privateEngine == nil else { return }
        privateEngine = CKSyncEngine(CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                               stateSerialization: privateState, delegate: self))
        sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(database: container.sharedCloudDatabase,
                                                              stateSerialization: sharedState, delegate: self))
        Task { await refreshAccountStatus() }
    }

    private func zoneID(_ tripID: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: tripID, ownerName: trips[tripID]?.ownerName ?? CKCurrentUserDefaultName)
    }

    private func engine(for tripID: String) -> CKSyncEngine? {
        trips[tripID]?.isOwned ?? true ? privateEngine : sharedEngine
    }

    private func enqueueSave(_ recordName: String, tripID: String) {
        guard trips[tripID]?.trip.isExample == false else { return }
        let id = CKRecord.ID(recordName: recordName, zoneID: zoneID(tripID))
        engine(for: tripID)?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    private func enqueueDelete(_ recordName: String, tripID: String) {
        guard trips[tripID]?.trip.isExample == false else { return }
        let id = CKRecord.ID(recordName: recordName, zoneID: zoneID(tripID))
        engine(for: tripID)?.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
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
                // Someone else's iCloud: don't keep the last person's trips on the phone.
                wipeSyncedData()
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions {
                let zone = deletion.zoneID
                if isPrivate && deletion.reason == .encryptedDataReset {
                    reupload(zone.zoneName)
                } else {
                    dropTrip(zone.zoneName)
                }
            }
            if !isPrivate {
                for modification in changes.modifications where trips[modification.zoneID.zoneName] == nil {
                    var entry = TripEntry(trip: Trip(id: modification.zoneID.zoneName, name: "Shared trip",
                                                     day: CalendarDay(Date(), calendar: .current)),
                                          ownerName: modification.zoneID.ownerName, isOwned: false)
                    entry.isShared = true
                    trips[entry.trip.id] = entry
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
        let tripID = id.zoneID.zoneName
        if id.recordName == TripRecords.tripRecordName, let entry = trips[tripID] {
            return TripRecords.record(entry.trip, zoneID: id.zoneID, systemFields: entry.systemFields)
        }
        if let entry = stops[id.recordName] {
            return TripRecords.record(entry.stop, zoneID: id.zoneID, systemFields: entry.systemFields)
        }
        return nil
    }

    private func apply(_ record: CKRecord) {
        let zone = record.recordID.zoneID
        let tripID = zone.zoneName
        if let share = record as? CKShare {
            applyShare(share, tripID: tripID)
            return
        }
        switch record.recordType {
        case TripRecords.Kind.trip:
            guard var trip = TripRecords.trip(from: record) else { return }
            trip.id = tripID
            var entry = trips[tripID] ?? TripEntry(trip: trip, ownerName: zone.ownerName,
                                                   isOwned: zone.ownerName == CKCurrentUserDefaultName)
            entry.trip = trip
            entry.systemFields = record.archivedSystemFields
            trips[tripID] = entry
        case TripRecords.Kind.stop:
            guard var stop = TripRecords.stop(from: record) else { return }
            stop.id = record.recordID.recordName
            stop.tripID = tripID
            stops[stop.id] = StopEntry(stop: stop, systemFields: record.archivedSystemFields)
        default:
            break
        }
    }

    private func applyShare(_ share: CKShare, tripID: String) {
        guard var entry = trips[tripID] else { return }
        entry.isShared = true
        entry.participants = share.participants
            .filter { $0.role != .owner && $0.acceptanceStatus == .accepted }
            .compactMap { participant in
                participant.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            }
        if !entry.isOwned {
            entry.readOnly = share.currentUserParticipant?.permission == .readOnly
        }
        trips[tripID] = entry
    }

    private func removeRecord(_ id: CKRecord.ID, type: CKRecord.RecordType) {
        switch type {
        case CKRecord.SystemType.share:
            trips[id.zoneID.zoneName]?.isShared = false
            trips[id.zoneID.zoneName]?.participants = []
        case TripRecords.Kind.stop:
            stops[id.recordName] = nil
        default:
            break
        }
    }

    private func storeSystemFields(of record: CKRecord) {
        let name = record.recordID.recordName
        if name == TripRecords.tripRecordName {
            trips[record.recordID.zoneID.zoneName]?.systemFields = record.archivedSystemFields
        } else {
            stops[name]?.systemFields = record.archivedSystemFields
        }
    }

    private func clearSystemFields(_ id: CKRecord.ID) {
        if id.recordName == TripRecords.tripRecordName {
            trips[id.zoneID.zoneName]?.systemFields = nil
        } else {
            stops[id.recordName]?.systemFields = nil
        }
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
                // The owner stopped sharing or deleted the trip.
                dropTrip(id.zoneID.zoneName)
            }
        case .unknownItem:
            clearSystemFields(id)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .permissionFailure:
            if trips[id.zoneID.zoneName]?.readOnly == false {
                trips[id.zoneID.zoneName]?.readOnly = true
                notice = "You can look at this trip, but changes won’t save. Ask the person who shared it to let you make changes."
            }
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
             .operationCancelled, .requestRateLimited:
            break // The engine retries these on its own.
        case .quotaExceeded:
            notice = "Your iCloud storage is full, so trip changes aren’t syncing."
        default:
            notice = "A trip change didn’t sync: \(error.localizedDescription)"
        }
    }

    private func dropTrip(_ id: String) {
        trips[id] = nil
        stops = stops.filter { $0.value.stop.tripID != id }
    }

    /// After an iCloud data reset, send a trip's records again from this phone.
    private func reupload(_ tripID: String) {
        guard trips[tripID] != nil else { return }
        trips[tripID]?.systemFields = nil
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID(tripID)))])
        enqueueSave(TripRecords.tripRecordName, tripID: tripID)
        for (id, entry) in stops where entry.stop.tripID == tripID {
            stops[id]?.systemFields = nil
            enqueueSave(id, tripID: tripID)
        }
    }

    /// Keeps the example trip, which never leaves the phone.
    private func wipeSyncedData() {
        let keep = Set(trips.values.filter(\.trip.isExample).map(\.trip.id))
        trips = trips.filter { keep.contains($0.key) }
        stops = stops.filter { keep.contains($0.value.stop.tripID) }
        privateState = nil
        sharedState = nil
        privateEngine = nil
        sharedEngine = nil
        startEngines()
        scheduleSave()
    }

    // MARK: Local file

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        trips = Dictionary(snapshot.trips.map { ($0.trip.id, $0) }, uniquingKeysWith: { _, last in last })
        stops = Dictionary(snapshot.stops.map { ($0.stop.id, $0) }, uniquingKeysWith: { _, last in last })
        legs = snapshot.legs
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
        let snapshot = Snapshot(trips: Array(trips.values), stops: Array(stops.values), legs: legs,
                                privateState: privateState, sharedState: sharedState)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Screenshot sample data

    private func loadScreenshotData() {
        let today = CalendarDay(Date(), calendar: .current)
        let example = TripExample.make(on: today)
        var entry = TripEntry(trip: example.trip, ownerName: CKCurrentUserDefaultName, isOwned: true)
        entry.isShared = true
        entry.participants = ["Julia"]
        trips = [example.trip.id: entry]
        stops = Dictionary(uniqueKeysWithValues: example.stops.map { ($0.id, StopEntry(stop: $0)) })
        selectedTripID = example.trip.id
        accountStatus = .available
    }
}

extension Coordinate {
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ location: CLLocationCoordinate2D) {
        self.init(latitude: location.latitude, longitude: location.longitude)
    }
}
