import AppIntents
import Foundation
import LittlesKit

/// A kid, for Siri and Shortcuts.
struct KidEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kid"
    static let defaultQuery = KidQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct KidQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [KidEntity] {
        AppModel.shared.state.kids.filter { identifiers.contains($0.id) }.map { KidEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [KidEntity] {
        AppModel.shared.state.kids.map { KidEntity(id: $0.id, name: $0.name) }
    }
}

enum DiaperChoice: String, AppEnum {
    case wet, dirty, both

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper"
    static let caseDisplayRepresentations: [DiaperChoice: DisplayRepresentation] = [
        .wet: "Wet", .dirty: "Dirty", .both: "Wet and dirty",
    ]

    var kind: DiaperKind {
        switch self {
        case .wet: return .wet
        case .dirty: return .dirty
        case .both: return .mixed
        }
    }
}

enum LastThing: String, AppEnum {
    case fed, ate, diaper, pooped, slept, medicine

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "What"
    static let caseDisplayRepresentations: [LastThing: DisplayRepresentation] = [
        .fed: "had a bottle or nursed", .ate: "ate", .diaper: "had a diaper change", .pooped: "pooped",
        .slept: "slept", .medicine: "had medicine",
    ]
}

struct LogBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a bottle"

    @Parameter(title: "Kid") var kid: KidEntity
    @Parameter(title: "Ounces", default: 4) var ounces: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let last = LittlesKit.Summary.last(model.state.logs, kidID: kid.id, kinds: [.bottle])
        model.save(LogEntry(kidID: kid.id, kind: .bottle, start: Date(), amountOz: ounces, milk: last?.milk ?? .formula))
        return .result(dialog: "Logged a \(model.units.volume(ounces)) bottle for \(kid.name).")
    }
}

struct LogDiaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a diaper"

    @Parameter(title: "Kid") var kid: KidEntity
    @Parameter(title: "Diaper", default: .wet) var diaper: DiaperChoice

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.save(LogEntry(kidID: kid.id, kind: .diaper, start: Date(), diaper: diaper.kind))
        return .result(dialog: "Logged a \(diaper.kind.title.lowercased()) diaper for \(kid.name).")
    }
}

struct StartSleepIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a nap"

    @Parameter(title: "Kid") var kid: KidEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.start(.sleep, kidID: kid.id)
        return .result(dialog: "Sleep timer started for \(kid.name). Sweet dreams.")
    }
}

struct WakeUpIntent: AppIntent {
    static let title: LocalizedStringResource = "End a nap"

    @Parameter(title: "Kid") var kid: KidEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let running = LittlesKit.Summary.running(model.state.logs, kidID: kid.id).first(where: { $0.kind == .sleep }) else {
            return .result(dialog: "\(kid.name) doesn't have a sleep timer running.")
        }
        model.stop(running.id)
        return .result(dialog: "\(kid.name) slept \(Dates.duration(Date().timeIntervalSince(running.start))).")
    }
}

struct LastTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "When did they last…"

    @Parameter(title: "Kid") var kid: KidEntity
    @Parameter(title: "What", default: .fed) var what: LastThing

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logs = AppModel.shared.state.logs
        let entry: LogEntry?
        switch what {
        case .fed: entry = LittlesKit.Summary.last(logs, kidID: kid.id, kinds: [.bottle, .nursing])
        case .ate: entry = LittlesKit.Summary.last(logs, kidID: kid.id, kinds: [.solids])
        case .diaper: entry = LittlesKit.Summary.last(logs, kidID: kid.id, kinds: [.diaper])
        case .pooped:
            entry = logs.filter { $0.kidID == kid.id && ($0.diaper?.isDirty == true || $0.potty == .poop || $0.potty == .both) }
                .max { $0.start < $1.start }
        case .slept: entry = LittlesKit.Summary.last(logs, kidID: kid.id, kinds: [.sleep])
        case .medicine: entry = LittlesKit.Summary.last(logs, kidID: kid.id, kinds: [.meds])
        }
        guard let entry else { return .result(dialog: "I don't see that logged for \(kid.name) yet.") }
        let time = entry.start.formatted(date: .omitted, time: .shortened)
        let ago = Dates.duration(Date().timeIntervalSince(entry.start))
        let detail = entry.detail(now: Date(), units: AppModel.shared.units)
        if entry.isRunning {
            return .result(dialog: "\(kid.name) has been asleep for \(ago), since \(time).")
        }
        let text = "\(ago) ago, at \(time)." + (detail.isEmpty ? "" : " \(detail).")
        return .result(dialog: "\(text)")
    }
}

struct LittlesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogBottleIntent(), phrases: [
            "Log a bottle for \(\.$kid) in \(.applicationName)",
            "Log a bottle in \(.applicationName)",
        ], shortTitle: "Log a bottle", systemImageName: "waterbottle.fill")
        AppShortcut(intent: LogDiaperIntent(), phrases: [
            "Log a diaper for \(\.$kid) in \(.applicationName)",
            "Log a diaper in \(.applicationName)",
        ], shortTitle: "Log a diaper", systemImageName: "checkmark.circle")
        AppShortcut(intent: StartSleepIntent(), phrases: [
            "\(\.$kid) is asleep in \(.applicationName)",
            "Start a nap in \(.applicationName)",
        ], shortTitle: "Start a nap", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: WakeUpIntent(), phrases: [
            "\(\.$kid) is awake in \(.applicationName)",
            "End the nap in \(.applicationName)",
        ], shortTitle: "End a nap", systemImageName: "sun.max.fill")
        AppShortcut(intent: LastTimeIntent(), phrases: [
            "When did \(\.$kid) last eat in \(.applicationName)",
            "When was the last feed in \(.applicationName)",
        ], shortTitle: "When did they last…", systemImageName: "clock")
    }
}
