import Foundation
import SwiftUI
import UIKit
import LittlesKit

/// Owns the family's data. Saves `family.json` in Application Support after
/// every change, re-syncs the reminders and the Lock Screen timers.
@MainActor
final class AppModel: ObservableObject {
    /// One model for the app and for Siri / Shortcuts, which run in the app's process.
    static let shared = AppModel()

    @Published var state: FamilyState {
        didSet { changed() }
    }
    /// The kid the Today, Food and Grow tabs show.
    @Published var kidID: String
    /// A message after a sync or import ("Added 12 entries from the other phone").
    @Published var banner: String?

    private let fileURL: URL
    let photosFolder: URL
    private var loading = true

    init() {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("family.json")
        photosFolder = folder.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)

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
        if loaded.charts.isEmpty && !loaded.deleted.contains("bedtime") { loaded.charts = RoutineChart.starters }
        // Ticks from past days aren't needed any more.
        let today = Dates.key(Date())
        let stale = Set(Agenda.stalePackKeys(loaded.packed, today: today))
        loaded.packed.removeAll { stale.contains($0) }
        let weekAgo = Dates.addDays(today, -14)
        loaded.chartDone.removeAll { $0 < weekAgo }
        state = loaded
        kidID = UserDefaults.standard.string(forKey: "kidID").flatMap { id in loaded.kids.contains { $0.id == id } ? id : nil }
            ?? loaded.kids.first?.id ?? ""
        if Screenshots.isActive { kidID = Screenshots.kidID }
        loading = false
    }

    private func changed() {
        guard !loading, !Screenshots.isActive else { return }
        do {
            let data = try JSONEncoder().encode(state)
            // Readable after the first unlock, so Siri and reminders work with the phone locked.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Littles: couldn't save: \(error)")
        }
        Notifier.sync(state)
        LiveTimers.sync(state)
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

    var units: Units {
        state.units
    }

    /// Kid names for a list of IDs: "Blake", or "Everyone" for an empty list.
    func names(_ ids: [String]) -> String {
        if ids.isEmpty || ids.count == state.kids.count { return state.kids.count > 1 ? "Everyone" : (state.kids.first?.name ?? "") }
        return ids.compactMap { kid($0)?.name }.joined(separator: " & ")
    }

    private func forget(_ id: String) {
        if !state.deleted.contains(id) { state.deleted.append(id) }
    }

    // MARK: Logs

    func save(_ entry: LogEntry) {
        var entry = entry
        entry.updated = Date()
        if let index = state.logs.firstIndex(where: { $0.id == entry.id }) {
            state.logs[index] = entry
        } else {
            state.logs.append(entry)
        }
    }

    func deleteLog(_ id: String) {
        if let photo = state.logs.first(where: { $0.id == id })?.photo, !photo.isEmpty { deletePhoto(photo) }
        state.logs.removeAll { $0.id == id }
        forget(id)
    }

    /// Starts a sleep or nursing timer, stopping any other timer of the same kind first.
    func start(_ kind: LogKind, kidID: String, side: Side? = nil, at date: Date = Date()) {
        stopAll(kind, kidID: kidID, at: date)
        state.logs.append(LogEntry(kidID: kidID, kind: kind, start: date, side: side, updated: Date()))
    }

    func stop(_ id: String, at date: Date = Date()) {
        guard let index = state.logs.firstIndex(where: { $0.id == id }) else { return }
        state.logs[index].end = max(date, state.logs[index].start)
        state.logs[index].updated = Date()
    }

    private func stopAll(_ kind: LogKind, kidID: String, at date: Date) {
        for index in state.logs.indices where state.logs[index].kidID == kidID && state.logs[index].kind == kind && state.logs[index].end == nil {
            state.logs[index].end = max(date, state.logs[index].start)
            state.logs[index].updated = Date()
        }
    }

    // MARK: Photos

    func savePhoto(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: photosFolder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func photo(_ name: String) -> UIImage? {
        guard !name.isEmpty else { return nil }
        return UIImage(contentsOfFile: photosFolder.appendingPathComponent(name).path)
    }

    func deletePhoto(_ name: String) {
        try? FileManager.default.removeItem(at: photosFolder.appendingPathComponent(name))
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
        for entry in state.logs where entry.kidID == id { forget(entry.id) }
        state.logs.removeAll { $0.kidID == id }
        state.milestones[id] = nil
        forget(id)
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
        forget(id)
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
        forget(id)
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
        forget(id)
    }

    func togglePacked(day: String, id: String) {
        let key = Agenda.packKey(day, id)
        if state.packed.contains(key) {
            state.packed.removeAll { $0 == key }
        } else {
            state.packed.append(key)
        }
    }

    func saveContact(_ contact: Contact) {
        if let index = state.contacts.firstIndex(where: { $0.id == contact.id }) {
            state.contacts[index] = contact
        } else {
            state.contacts.append(contact)
        }
    }

    func deleteContact(_ id: String) {
        state.contacts.removeAll { $0.id == id }
        forget(id)
    }

    func addShopping(_ title: String, list: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !state.shopping.contains(where: { !$0.done && $0.title.lowercased() == trimmed.lowercased() }) else { return }
        state.shopping.append(ShoppingItem(title: trimmed, list: list))
    }

    func toggleShopping(_ id: String) {
        guard let index = state.shopping.firstIndex(where: { $0.id == id }) else { return }
        state.shopping[index].done.toggle()
    }

    func clearBought() {
        for item in state.shopping where item.done { forget(item.id) }
        state.shopping.removeAll { $0.done }
    }

    // MARK: Charts

    func toggleChartStep(chartID: String, kidID: String, step: Int, day: String = Dates.key(Date())) {
        let key = RoutineChart.key(day: day, chartID: chartID, kidID: kidID, step: step)
        if state.chartDone.contains(key) {
            state.chartDone.removeAll { $0 == key }
        } else {
            state.chartDone.append(key)
        }
    }

    func saveChart(_ chart: RoutineChart) {
        if let index = state.charts.firstIndex(where: { $0.id == chart.id }) {
            state.charts[index] = chart
        } else {
            state.charts.append(chart)
        }
    }

    func deleteChart(_ id: String) {
        state.charts.removeAll { $0.id == id }
        forget(id)
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

    // MARK: Milestones and health

    func status(_ milestoneID: String, kidID: String) -> MilestoneStatus? {
        state.milestones[kidID]?[milestoneID]
    }

    func setStatus(_ status: MilestoneStatus?, milestoneID: String, kidID: String) {
        var marks = state.milestones[kidID] ?? [:]
        marks[milestoneID] = status
        state.milestones[kidID] = marks
    }

    func setVaccine(_ doseID: String, kidID: String, day: String?) {
        var doses = state.vaccines[kidID] ?? [:]
        doses[doseID] = day
        state.vaccines[kidID] = doses
    }

    // MARK: Food

    func mealSeed(_ kidID: String) -> Int {
        state.mealSeeds[kidID] ?? 0
    }

    func shuffleMeals(_ kidID: String) {
        state.mealSeeds[kidID] = mealSeed(kidID) + 1
    }

    // MARK: Sync and export

    /// The family file to send to another phone.
    func syncFileURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Littles family \(Dates.key(Date())).littles")
        guard let data = try? JSONEncoder().encode(state), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    /// Merges a family file from another phone.
    func importSync(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let theirs = try? JSONDecoder().decode(FamilyState.self, from: data) else {
            banner = "That file couldn't be read."
            return
        }
        let result = FamilySync.merge(state, theirs)
        state = result.state
        banner = "Synced: \(result.newLogs) log entr\(result.newLogs == 1 ? "y" : "ies") and \(result.newOther) other item\(result.newOther == 1 ? "" : "s") from the other phone. Photos stay on the phone that took them."
    }

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
