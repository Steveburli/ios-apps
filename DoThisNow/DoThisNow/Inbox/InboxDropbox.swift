import AppIntents
import Foundation

/// Where Shortcuts, Siri and the Share button leave tasks for the Inbox.
/// The intent can run while the app is closed, so it writes a small file
/// that the app picks up the next time it's active.
enum InboxDropbox {
    struct Drop: Codable {
        var title: String
        var notes: String
        var minutes: Int?
        var at: Date
    }

    /// Posted when a task arrives while the app is running.
    static let arrived = Notification.Name("InboxDropbox.arrived")

    private static let lock = NSLock()

    private static var url: URL {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent("inbox-drops.json")
    }

    static func add(_ drop: Drop) {
        lock.lock()
        defer { lock.unlock() }
        var drops = read()
        drops.append(drop)
        if let data = try? JSONEncoder().encode(drops) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Everything waiting, removed from the dropbox.
    static func take() -> [Drop] {
        lock.lock()
        defer { lock.unlock() }
        let drops = read()
        if !drops.isEmpty { try? FileManager.default.removeItem(at: url) }
        return drops
    }

    private static func read() -> [Drop] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Drop].self, from: data)) ?? []
    }
}

/// "Add to Do This Now Inbox", for Shortcuts, Siri, and a Share-button shortcut.
struct AddToInboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Do This Now Inbox"
    static var description = IntentDescription("Adds a task to the Inbox on Do This Now’s Day tab, ready to drag onto your day. The first line is the task; anything after it becomes notes.")

    @Parameter(title: "Task", requestValueDialog: "What should I add?")
    var task: String

    @Parameter(title: "Minutes", description: "How long it will take. Leave it empty and Do This Now estimates.")
    var minutes: Int?

    @Parameter(title: "Notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$task) to the Inbox") {
            \.$minutes
            \.$notes
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let lines = task.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else {
            throw $task.needsValueError("What should I add?")
        }
        let title = String(first.prefix(200))
        let extra = lines.dropFirst().joined(separator: "\n")
        let allNotes = [extra, notes ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        InboxDropbox.add(InboxDropbox.Drop(title: title, notes: allNotes, minutes: minutes.flatMap { $0 > 0 ? $0 : nil }, at: Date()))
        await MainActor.run {
            NotificationCenter.default.post(name: InboxDropbox.arrived, object: nil)
        }
        return .result(dialog: "Added “\(title)” to your Inbox.")
    }
}

struct DoThisNowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToInboxIntent(),
                    phrases: ["Add a task to \(.applicationName)", "Add to my \(.applicationName) Inbox"],
                    shortTitle: "Add to Inbox",
                    systemImageName: "tray.and.arrow.down")
    }
}
