import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// Built into both the app and the widgets extension (Shared/ is in both targets).
// It doesn't import DoThisNowKit, so the extension stays small.

/// What the widgets and the Lock Screen need to know about Track timers, kept
/// in the App Group that the app and the widgets extension share.
///
/// The app writes `snapshot.json` after every change. When a widget button
/// runs while the app can't (the intent ran inside the extension), the
/// extension updates the snapshot itself so the widget shows the change at
/// once, and leaves the command in `commands.json`. The app replays those
/// commands, with the times they were tapped, the next time it runs.
enum TimerBridge {
    static let appGroup = "group.com.steveburlison.dothisnow"
    /// The kind string of every widget, for reloading them.
    static let widgetKinds = ["DoThisNowTimer", "DoThisNowStartButtons"]

    struct StartButton: Codable, Equatable, Hashable, Identifiable {
        var id: String
        var name: String
        var symbol: String
    }

    struct Run: Codable, Equatable, Hashable {
        var activityID: String?
        var title: String
        var symbol: String
        var startedAt: Date
    }

    struct Snapshot: Codable, Equatable {
        /// The Track timer that's running.
        var running: Run?
        /// The start buttons picked in Settings, in Track order.
        var buttons: [StartButton] = []
        /// False until the app has written once, so a fresh widget can say "Open Do This Now".
        var ready = false
    }

    enum Command: Codable, Equatable {
        /// Start this activity, or stop it if it's the one running.
        case toggle(String, at: Date)
        case stop(at: Date)
    }

    private static let lock = NSLock()

    static var folder: URL {
        if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return shared
        }
        // No App Group (an unsigned build): the app still works, the widgets just can't see it.
        return (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
    }

    private static var snapshotURL: URL { folder.appendingPathComponent("timer-snapshot.json") }
    private static var commandsURL: URL { folder.appendingPathComponent("timer-commands.json") }

    // MARK: Snapshot

    static func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return readSnapshot()
    }

    /// Saves the snapshot and refreshes the widgets. Returns false when nothing changed.
    @discardableResult
    static func write(_ snapshot: Snapshot) -> Bool {
        lock.lock()
        let changed = readSnapshot() != snapshot
        if changed, let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
        lock.unlock()
        if changed { reloadWidgets() }
        return changed
    }

    private static func readSnapshot() -> Snapshot {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Snapshot() }
        return snapshot
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        for kind in widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        #endif
    }

    // MARK: Commands waiting for the app

    static var hasCommands: Bool {
        FileManager.default.fileExists(atPath: commandsURL.path)
    }

    /// Everything waiting, oldest first, removed from the file.
    static func takeCommands() -> [Command] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: commandsURL) else { return [] }
        try? FileManager.default.removeItem(at: commandsURL)
        return (try? JSONDecoder().decode([Command].self, from: data)) ?? []
    }

    /// Runs a command without the app: updates the snapshot the way the app
    /// would and queues the command for the app. Returns the new running timer.
    @discardableResult
    static func queue(_ command: Command) -> Run? {
        lock.lock()
        var commands: [Command] = []
        if let data = try? Data(contentsOf: commandsURL) {
            commands = (try? JSONDecoder().decode([Command].self, from: data)) ?? []
        }
        commands.append(command)
        if let data = try? JSONEncoder().encode(commands) {
            try? data.write(to: commandsURL, options: .atomic)
        }
        var snapshot = readSnapshot()
        switch command {
        case .stop:
            snapshot.running = nil
        case .toggle(let id, let at):
            if snapshot.running?.activityID == id {
                snapshot.running = nil
            } else {
                let button = snapshot.buttons.first { $0.id == id }
                snapshot.running = Run(activityID: id, title: button?.name ?? "Timer", symbol: button?.symbol ?? "timer",
                                       startedAt: at)
            }
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
        lock.unlock()
        reloadWidgets()
        return snapshot.running
    }
}

/// Where widget and Lock Screen buttons go. The app sets `handler` as soon as
/// it launches; inside the widgets extension it stays nil and the command goes
/// through `TimerBridge.queue` instead.
@MainActor
enum TimerControl {
    static var handler: ((TimerBridge.Command) -> Void)?

    static func run(_ command: TimerBridge.Command) async {
        if let handler {
            handler(command)
            return
        }
        let running = TimerBridge.queue(command)
        await LiveTimers.showTrack(running)
    }
}
