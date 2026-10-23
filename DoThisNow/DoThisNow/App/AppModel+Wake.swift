import SwiftUI
import DoThisNowKit

/// The Wake tab: the morning plan, and the alarm you scan to turn off.
extension AppModel {
    /// The next time the alarm rings, not counting backups.
    var nextAlarm: AlarmFire? {
        engine.alarmFires().first { $0.backup == 0 }
    }

    /// Keeps the phone's alarms matching the plan. Cheap when nothing changed.
    func syncAlarms() {
        WakeAlarms.sync(engine.alarmFires(), scan: state.wake.alarm.needsScan)
    }

    /// Opens the scanner while this morning's alarm is waiting for a scan,
    /// or when its "Scan to stop" button opened the app.
    func checkAlarm() {
        guard scanMode == nil, !Screenshots.isActive else { return }
        let requested = UserDefaults.standard.bool(forKey: WakeAlarms.scanRequestedKey)
        if requested { UserDefaults.standard.set(false, forKey: WakeAlarms.scanRequestedKey) }
        if engine.ringingAlarm() != nil || (requested && state.wake.alarm.needsScan) {
            sheet = nil
            scanMode = .stopAlarm
        }
    }

    func saveWake(_ change: (inout WakeSettings) -> Void) {
        change(&state.wake)
        commit()
    }

    func setAlarm(on: Bool) async {
        if on {
            guard await WakeAlarms.authorize() else {
                show("Alarms aren’t allowed. Turn them on for Do This Now in the Settings app.")
                return
            }
        }
        state.wake.alarm.on = on
        commit()
        if on, let next = nextAlarm {
            show("Alarm set for \(formats.when(next.date, now: Date()))")
        }
    }

    /// Checks a scan. While the alarm is waiting, the right code turns it off.
    func scanned(_ payload: String) -> Bool {
        guard state.wake.alarm.codes.contains(where: { $0.payload == payload }) else { return false }
        stopAlarm()
        return true
    }

    /// Turns off the morning that's ringing, or the next one if you're up early.
    func stopAlarm() {
        scanMode = nil
        if engine.ringingAlarm() == nil && WakeAlarms.isTesting {
            WakeAlarms.endTest()
            show("Test passed. That’s how you’ll turn it off.")
            return
        }
        let morning = engine.ringingAlarm() ?? nextAlarm?.morning ?? today
        state.wake.alarm.stoppedOn = morning
        commit()
        show(morning == today ? "Alarm off. Good morning!" : "The \(formats.weekdayName(morning)) alarm is off")
    }

    func addCode(name: String, payload: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.wake.alarm.codes.contains(where: { $0.payload == payload }) {
            show("That code is already saved")
            return
        }
        state.wake.alarm.codes.append(WakeCode(name: name.isEmpty ? "Code \(state.wake.alarm.codes.count + 1)" : name, payload: payload))
        commit()
        show("Saved. Scan it to turn the alarm off.")
    }

    func deleteCode(_ id: String) {
        state.wake.alarm.codes.removeAll { $0.id == id }
        commit()
    }

    /// Uses the suggested wake-up time and bedtime for the Day planner too.
    func useWakePlan(_ plan: WakePlan) {
        let wake = Int(plan.wake.rounded())
        var bed = Int(plan.inBed.rounded())
        if bed < 0 { bed += 1440 }
        state.settings.wake = ((wake % 1440) + 1440) % 1440
        state.settings.bed = bed % 1440
        commit()
        show("Your day now starts at \(formats.time(plan.day, plan.wake)) and bedtime is \(formats.time(plan.day, plan.inBed))")
    }

    func testAlarm() async {
        guard await WakeAlarms.authorize() else {
            show("Alarms aren’t allowed. Turn them on for Do This Now in the Settings app.")
            return
        }
        await WakeAlarms.test(scan: state.wake.alarm.needsScan)
        show("A test alarm will ring in about a minute. Lock the phone to see it.")
    }
}
