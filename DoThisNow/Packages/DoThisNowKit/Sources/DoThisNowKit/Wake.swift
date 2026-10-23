import Foundation

/// One thing you do between waking up and heading out.
public struct RoutineStep: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// The Track activity whose timings set its length.
    public var activityID: String?
    /// Minutes you set yourself; nil uses your timings, or a guess.
    public var minutes: Int?

    public init(id: String = newID(), title: String, activityID: String? = nil, minutes: Int? = nil) {
        self.id = id
        self.title = title
        self.activityID = activityID
        self.minutes = minutes
    }

    private enum CodingKeys: String, CodingKey { case id, title, activityID, minutes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  activityID: try c.decodeIfPresent(String.self, forKey: .activityID),
                  minutes: try c.decodeIfPresent(Int.self, forKey: .minutes))
    }
}

/// A barcode or QR code that turns the alarm off when you scan it.
public struct WakeCode: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var payload: String

    public init(id: String = newID(), name: String, payload: String) {
        self.id = id
        self.name = name
        self.payload = payload
    }
}

public struct AlarmSettings: Codable, Equatable, Sendable {
    public var on = false
    /// Ring at the suggested wake-up time; otherwise at `time`.
    public var followPlan = true
    /// Minutes after midnight.
    public var time = 6 * 60 + 30
    /// 0 = Sunday … 6 = Saturday.
    public var days: [Int] = [1, 2, 3, 4, 5]
    public var requireScan = true
    public var codes: [WakeCode] = []
    /// Minutes between the backup alarms that ring until you scan.
    public var backupEvery = 2
    public var backups = 10
    /// The morning a scan turned the alarm off.
    public var stoppedOn: CalendarDay?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case on, followPlan, time, days, requireScan, codes, backupEvery, backups, stoppedOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? on
        followPlan = try c.decodeIfPresent(Bool.self, forKey: .followPlan) ?? followPlan
        time = try c.decodeIfPresent(Int.self, forKey: .time) ?? time
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? days
        requireScan = try c.decodeIfPresent(Bool.self, forKey: .requireScan) ?? requireScan
        codes = try c.decodeIfPresent([WakeCode].self, forKey: .codes) ?? []
        backupEvery = try c.decodeIfPresent(Int.self, forKey: .backupEvery) ?? backupEvery
        backups = try c.decodeIfPresent(Int.self, forKey: .backups) ?? backups
        stoppedOn = try c.decodeIfPresent(CalendarDay.self, forKey: .stoppedOn)
    }

    /// Scanning only works once there's a code to scan.
    public var needsScan: Bool {
        requireScan && !codes.isEmpty
    }
}

/// Sleep goal, morning routine and alarm.
public struct WakeSettings: Codable, Equatable, Sendable {
    public var sleepMinutes = 8 * 60
    /// How long it takes you to fall asleep.
    public var fallAsleep = 15
    /// Slack between finishing the routine and leaving.
    public var buffer = 10
    /// Count a commute before work.
    public var commuteOn = true
    public var commute = RoutineStep(id: "commute", title: "Commute to work")
    public var routine: [RoutineStep] = WakeSettings.starterRoutine
    public var alarm = AlarmSettings()

    public static let starterRoutine = [
        RoutineStep(id: "routine-shower", title: "Shower"),
        RoutineStep(id: "routine-dressed", title: "Get dressed"),
        RoutineStep(id: "routine-breakfast", title: "Breakfast"),
        RoutineStep(id: "routine-teeth", title: "Brush teeth"),
    ]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case sleepMinutes, fallAsleep, buffer, commuteOn, commute, routine, alarm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sleepMinutes = try c.decodeIfPresent(Int.self, forKey: .sleepMinutes) ?? sleepMinutes
        fallAsleep = try c.decodeIfPresent(Int.self, forKey: .fallAsleep) ?? fallAsleep
        buffer = try c.decodeIfPresent(Int.self, forKey: .buffer) ?? buffer
        commuteOn = try c.decodeIfPresent(Bool.self, forKey: .commuteOn) ?? commuteOn
        commute = try c.decodeIfPresent(RoutineStep.self, forKey: .commute) ?? commute
        routine = try c.decodeIfPresent([RoutineStep].self, forKey: .routine) ?? routine
        alarm = try c.decodeIfPresent(AlarmSettings.self, forKey: .alarm) ?? AlarmSettings()
    }
}

/// When to wake up on one morning, and when to be asleep the night before.
public struct WakePlan: Sendable {
    public struct Step: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let estimate: Estimate
    }

    /// The morning being planned.
    public let day: CalendarDay
    /// When you have to head out, in minutes after that midnight. nil when
    /// nothing is booked.
    public let leave: Double?
    /// Why: "Work starts at 9:00 AM", "Leave for Dentist at 8:15 AM".
    public let reason: String
    public let steps: [Step]
    /// The commute, when the morning ends with work.
    public let commute: Step?
    public let buffer: Int
    /// Minutes of morning routine.
    public let routine: Int
    /// Minutes after midnight of `day`.
    public let wake: Double
    /// When to be asleep: your sleep goal before `wake`. Negative means the
    /// evening before.
    public let asleep: Double
    /// When to get into bed: `asleep` minus the time it takes to drift off.
    public let inBed: Double
}

/// One ring of the alarm.
public struct AlarmFire: Equatable, Sendable {
    public let date: Date
    public let morning: CalendarDay
    /// 0 for the alarm itself, then 1, 2… for the backups.
    public let backup: Int
}

extension Engine {
    /// Works back from the first thing you have to leave for: work (minus
    /// the commute) or an earlier event. Then the buffer and the morning
    /// routine, rounded down to five minutes, give the wake-up time, and the
    /// sleep goal gives bedtime. With nothing booked, it's your usual
    /// wake-up time from Settings.
    public func wakePlan(for day: CalendarDay) -> WakePlan {
        let wake = state.wake
        let settings = state.settings
        let steps = wake.routine.map { step in
            WakePlan.Step(id: step.id, title: step.title,
                          estimate: state.estimate(title: step.title, activityID: step.activityID, custom: step.minutes))
        }
        let routine = steps.reduce(0) { $0 + $1.estimate.minutes }

        var leave: Double?
        var reason = "Nothing booked, so your usual wake-up time"
        var commute: WakePlan.Step?
        if settings.work.on && settings.work.days.contains(day.weekdayIndex(calendar: calendar)) && !state.dayConfig(day).noWork {
            let start = Double(settings.work.start)
            var travel = 0.0
            if wake.commuteOn {
                let step = wake.commute
                let estimate = state.estimate(title: step.title, activityID: step.activityID, custom: step.minutes)
                commute = WakePlan.Step(id: step.id, title: step.title, estimate: estimate)
                travel = Double(estimate.minutes)
            }
            leave = start - travel
            reason = "Work starts at \(formats.time(day, start))"
        }
        let firstEvent = state.events
            .filter { $0.day == day }
            .map { (at: Double($0.arrive ?? $0.start) - Double(max(0, $0.travel)), title: $0.title) }
            .min { $0.at < $1.at }
        if let firstEvent, firstEvent.at < (leave ?? .infinity) {
            leave = firstEvent.at
            reason = "Leave for \(firstEvent.title) at \(formats.time(day, firstEvent.at))"
            commute = nil
        }

        let base = leave.map { $0 - Double(wake.buffer + routine) } ?? Double(settings.wake)
        let wakeAt = (base / 5).rounded(.down) * 5
        let asleep = wakeAt - Double(wake.sleepMinutes)
        return WakePlan(day: day, leave: leave, reason: reason, steps: steps, commute: commute, buffer: wake.buffer,
                        routine: routine, wake: wakeAt, asleep: asleep, inBed: asleep - Double(wake.fallAsleep))
    }

    /// The morning to plan for: today until its wake-up time, then tomorrow.
    public func wakeMorning() -> CalendarDay {
        nowMinute < wakePlan(for: today).wake ? today : today.adding(days: 1, calendar: calendar)
    }

    /// When the alarm rings on `morning`, or nil when it's off that day.
    public func alarmTime(on morning: CalendarDay) -> Date? {
        let alarm = state.wake.alarm
        guard alarm.on, alarm.days.contains(morning.weekdayIndex(calendar: calendar)) else { return nil }
        let minute = alarm.followPlan ? wakePlan(for: morning).wake : Double(alarm.time)
        return morning.date(atMinute: minute, calendar: calendar)
    }

    /// Every ring still to come over the next `days` mornings. When a scan
    /// turns the alarm off, the next morning also gets backups that keep
    /// ringing until you scan, since iPhone always shows its own Stop
    /// button. Later mornings get theirs once they're next.
    public func alarmFires(days: Int = 7) -> [AlarmFire] {
        let alarm = state.wake.alarm
        var out: [AlarmFire] = []
        var backedUp = !alarm.needsScan
        for offset in 0..<max(0, days) {
            let morning = today.adding(days: offset, calendar: calendar)
            guard alarm.stoppedOn != morning, let ring = alarmTime(on: morning) else { continue }
            var fires = [AlarmFire(date: ring, morning: morning, backup: 0)]
            if !backedUp {
                fires += stride(from: 1, through: alarm.backups, by: 1).map { n in
                    AlarmFire(date: ring.addingTimeInterval(Double(n * max(1, alarm.backupEvery) * 60)), morning: morning, backup: n)
                }
            }
            let upcoming = fires.filter { $0.date > now }
            if upcoming.isEmpty { continue }
            backedUp = true
            out += upcoming
        }
        return out
    }

    /// This morning, while its alarm is ringing or between backups and
    /// still waiting for a scan.
    public func ringingAlarm() -> CalendarDay? {
        let alarm = state.wake.alarm
        guard alarm.needsScan, alarm.stoppedOn != today, let ring = alarmTime(on: today) else { return nil }
        let end = ring.addingTimeInterval(Double((alarm.backups * max(1, alarm.backupEvery) + 10) * 60))
        return now >= ring && now <= end ? today : nil
    }
}
