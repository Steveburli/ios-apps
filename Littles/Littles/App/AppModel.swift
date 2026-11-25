import Foundation
import SwiftUI
import LittlesKit

/// Owns the family's data. Saves `family.json` in Application Support after
/// every change, and re-syncs the schedule reminders.
@MainActor
final class AppModel: ObservableObject {
    @Published var state: FamilyState {
        didSet { changed() }
    }
    /// The kid the Today, Food and Grow tabs show.
    @Published var kidID: String

    private let fileURL: URL
    private var loading = true

    init() {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("family.json")

        var loaded: FamilyState
        if Screenshots.isActive {
            loaded = Sample.family(now: Date())
        } else if let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode(FamilyState.self, from: data) {
            loaded = decoded
        } else {
            loaded = FamilyState.starter()
        }
        if loaded.kids.isEmpty { loaded.kids = FamilyState.starter().kids }
        // Pack-list ticks from past days aren't needed any more.
        let stale = Set(Agenda.stalePackKeys(loaded.packed, today: Dates.key(Date())))
        loaded.packed.removeAll { stale.contains($0) }
        state = loaded
        kidID = UserDefaults.standard.string(forKey: "kidID").flatMap { id in loaded.kids.contains { $0.id == id } ? id : nil }
            ?? loaded.kids.first?.id ?? ""
        if Screenshots.isActive { kidID = Screenshots.kidID }
        loading = false
    }

    private func changed() {
        guard !loading, !Screenshots.isActive else { return }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Littles: couldn't save: \(error)")
        }
        Notifier.sync(state)
    }

    func select(_ id: String) {
        kidID = id
        UserDefaults.standard.set(id, forKey: "kidID")
    }

    var kid: Kid? {
        state.kid(kidID) ?? state.kids.first
    }

    func kid(_ id: String) -> Kid? {
        state.kid(id)
    }

    /// Kid names for a list of IDs: "Blake", or "Everyone" for an empty list.
    func names(_ ids: [String]) -> String {
        if ids.isEmpty || ids.count == state.kids.count { return state.kids.count > 1 ? "Everyone" : (state.kids.first?.name ?? "") }
        return ids.compactMap { kid($0)?.name }.joined(separator: " & ")
    }

    // MARK: Logs

    func save(_ entry: LogEntry) {
        if let index = state.logs.firstIndex(where: { $0.id == entry.id }) {
            state.logs[index] = entry
        } else {
            state.logs.append(entry)
        }
    }

    func deleteLog(_ id: String) {
        state.logs.removeAll { $0.id == id }
    }

    /// Starts a sleep or nursing timer, stopping any other timer of the same kind first.
    func start(_ kind: LogKind, kidID: String, side: Side? = nil, at date: Date = Date()) {
        stopAll(kind, kidID: kidID, at: date)
        state.logs.append(LogEntry(kidID: kidID, kind: kind, start: date, side: side))
    }

    func stop(_ id: String, at date: Date = Date()) {
        guard let index = state.logs.firstIndex(where: { $0.id == id }) else { return }
        state.logs[index].end = max(date, state.logs[index].start)
    }

    private func stopAll(_ kind: LogKind, kidID: String, at date: Date) {
        for index in state.logs.indices where state.logs[index].kidID == kidID && state.logs[index].kind == kind && state.logs[index].end == nil {
            state.logs[index].end = max(date, state.logs[index].start)
        }
    }

    // MARK: Kids

    func saveKid(_ kid: Kid) {
        if let index = state.kids.firstIndex(where: { $0.id == kid.id }) {
            state.kids[index] = kid
        } else {
            state.kids.append(kid)
        }
    }

    func deleteKid(_ id: String) {
        guard state.kids.count > 1 else { return }
        state.kids.removeAll { $0.id == id }
        state.logs.removeAll { $0.kidID == id }
        state.milestones[id] = nil
        if kidID == id { select(state.kids.first?.id ?? "") }
    }

    // MARK: Schedule

    func saveRoutine(_ item: RoutineItem) {
        if let index = state.routines.firstIndex(where: { $0.id == item.id }) {
            state.routines[index] = item
        } else {
            state.routines.append(item)
        }
        if item.remind != nil { Notifier.requestPermission() }
    }

    func deleteRoutine(_ id: String) {
        state.routines.removeAll { $0.id == id }
    }

    func saveEvent(_ event: OneOffEvent) {
        if let index = state.events.firstIndex(where: { $0.id == event.id }) {
            state.events[index] = event
        } else {
            state.events.append(event)
        }
    }

    func deleteEvent(_ id: String) {
        state.events.removeAll { $0.id == id }
    }

    func savePackItem(_ item: PackItem) {
        if let index = state.packItems.firstIndex(where: { $0.id == item.id }) {
            state.packItems[index] = item
        } else {
            state.packItems.append(item)
        }
    }

    func deletePackItem(_ id: String) {
        state.packItems.removeAll { $0.id == id }
    }

    func togglePacked(day: String, id: String) {
        let key = Agenda.packKey(day, id)
        if state.packed.contains(key) {
            state.packed.removeAll { $0 == key }
        } else {
            state.packed.append(key)
        }
    }

    // MARK: Activities

    func markDone(_ activityID: String, kidIDs: [String], hit: Bool) {
        state.activitiesDone.append(ActivityDone(activityID: activityID, day: Dates.key(Date()), kidIDs: kidIDs, hit: hit))
    }

    func toggleFavorite(_ activityID: String) {
        if state.favoriteActivities.contains(activityID) {
            state.favoriteActivities.removeAll { $0 == activityID }
        } else {
            state.favoriteActivities.append(activityID)
        }
    }

    func timesDone(_ activityID: String) -> Int {
        state.activitiesDone.filter { $0.activityID == activityID }.count
    }

    // MARK: Milestones

    func status(_ milestoneID: String, kidID: String) -> MilestoneStatus? {
        state.milestones[kidID]?[milestoneID]
    }

    func setStatus(_ status: MilestoneStatus?, milestoneID: String, kidID: String) {
        var marks = state.milestones[kidID] ?? [:]
        marks[milestoneID] = status
        state.milestones[kidID] = marks
    }

    // MARK: Export

    /// The whole family file, for Settings > Export.
    func exportURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Littles \(Dates.key(Date())).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state), (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}
