import SwiftUI
import AppIntents
import UserNotifications
import DoThisNowKit
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Puts the wake-up alarm on the phone. On iOS 26 and later it's a real
/// alarm (AlarmKit): it rings through silent mode and Focus and fills the
/// Lock Screen. Before that, it's a run of notifications.
///
/// iPhone always shows its own Stop control on an alarm, so scanning works
/// by backups: they keep ringing every couple of minutes until a scan in
/// the app turns them off.
@MainActor
enum WakeAlarms {
    /// Set by the alarm's "Scan to stop" button, read when the app opens.
    static let scanRequestedKey = "scanRequested"
    private static let signatureKey = "alarmSignature"
    private static let testKey = "alarmTestUntil"
    private static let notificationPrefix = "wake-alarm-"

    /// Asks for permission to ring alarms (or post notifications before iOS 26).
    static func authorize() async -> Bool {
        guard !Screenshots.isActive else { return true }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await AlarmKitAlarms.authorize()
        }
        #endif
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Replaces the scheduled alarms with `fires`, unless they already match.
    static func sync(_ fires: [AlarmFire], scan: Bool) {
        guard !Screenshots.isActive else { return }
        let signature = (scan ? "scan " : "plain ") + fires.map { "\(Int($0.date.timeIntervalSince1970)):\($0.backup)" }.joined(separator: ",")
        guard signature != UserDefaults.standard.string(forKey: signatureKey) else { return }
        Task {
            var done = false
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *), AlarmKitAlarms.isAuthorized {
                done = await AlarmKitAlarms.replace(fires, scan: scan)
                removeNotifications()
            }
            #endif
            if !done {
                done = await replaceNotifications(fires, scan: scan)
            }
            if done {
                UserDefaults.standard.set(signature, forKey: signatureKey)
            }
        }
    }

    /// A one-off alarm in a minute, to see and hear it.
    static func test(scan: Bool) async {
        UserDefaults.standard.set(Date().addingTimeInterval(10 * 60), forKey: testKey)
        let date = Date().addingTimeInterval(60)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), AlarmKitAlarms.isAuthorized {
            await AlarmKitAlarms.test(at: date, scan: scan)
            return
        }
        #endif
        let content = notificationContent(scan: scan, backup: false)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "wake-test", content: content, trigger: trigger))
    }

    /// A test alarm went off in the last ten minutes.
    static var isTesting: Bool {
        guard let until = UserDefaults.standard.object(forKey: testKey) as? Date else { return false }
        return until > Date()
    }

    static func endTest() {
        UserDefaults.standard.removeObject(forKey: testKey)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            AlarmKitAlarms.stopTest()
        }
        #endif
    }

    // MARK: Notifications, before iOS 26

    private static func notificationContent(scan: Bool, backup: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = backup ? "Still in bed?" : "Time to get up"
        content.body = scan ? "Open Do This Now and scan your code to turn this off." : "Good morning."
        content.sound = .default
        return content
    }

    private static func replaceNotifications(_ fires: [AlarmFire], scan: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        removeNotifications()
        // iOS keeps 64 pending notifications; leave room for the others.
        for (index, fire) in fires.prefix(20).enumerated() {
            let interval = fire.date.timeIntervalSinceNow
            guard interval >= 1 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: notificationPrefix + "\(index)",
                                                content: notificationContent(scan: scan, backup: fire.backup > 0), trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                return false
            }
        }
        return true
    }

    private static func removeNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<20).map { notificationPrefix + "\($0)" })
    }
}

/// Opens the app on the scanner. The alarm's second button runs it.
struct OpenScannerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Scan to turn off the alarm"
    static var description = IntentDescription("Opens Do This Now on the scanner.")
    static var openAppWhenRun = true
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: WakeAlarms.scanRequestedKey)
        return .result()
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
@MainActor
enum AlarmKitAlarms {
    private static var testID: UUID?

    static var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    static func authorize() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        default:
            return false
        }
    }

    /// Cancels every alarm this app set (except a running test) and sets `fires`.
    static func replace(_ fires: [AlarmFire], scan: Bool) async -> Bool {
        let manager = AlarmManager.shared
        for alarm in (try? manager.alarms) ?? [] where alarm.id != testID {
            try? manager.cancel(id: alarm.id)
        }
        var ok = true
        for fire in fires {
            do {
                _ = try await manager.schedule(id: UUID(), configuration: configuration(at: fire.date, scan: scan, backup: fire.backup > 0))
            } catch {
                ok = false
            }
        }
        return ok
    }

    static func test(at date: Date, scan: Bool) async {
        let id = UUID()
        testID = id
        _ = try? await AlarmManager.shared.schedule(id: id, configuration: configuration(at: date, scan: scan, backup: false))
    }

    static func stopTest() {
        guard let testID else { return }
        try? AlarmManager.shared.cancel(id: testID)
        self.testID = nil
    }

    private static func configuration(at date: Date, scan: Bool, backup: Bool) -> AlarmManager.AlarmConfiguration<WakeAlarmMetadata> {
        let title: LocalizedStringResource = scan ? (backup ? "Still in bed? Scan your code" : "Time to get up. Scan your code") : "Time to get up"
        let button = AlarmButton(text: scan ? "Scan to stop" : "Open", textColor: .white,
                                 systemImageName: scan ? "barcode.viewfinder" : "sun.max.fill")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: button, secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(title: title, stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
                                            secondaryButton: button, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes<WakeAlarmMetadata>(presentation: AlarmPresentation(alert: alert), metadata: WakeAlarmMetadata(),
                                                            tintColor: Color(red: 0.88, green: 0.26, blue: 0.11))
        return .alarm(schedule: .fixed(date), attributes: attributes, stopIntent: nil, secondaryIntent: OpenScannerIntent())
    }
}
#endif
