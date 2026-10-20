import Foundation

/// A stretch of a day in minutes after midnight. Values past 1440 run into
/// the night.
public struct TimeSpan: Equatable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var length: Double { end - start }
}

/// Something the planner tries to fit into the day: one task, or an errand run.
public struct Chunk: Identifiable, Equatable, Sendable {
    public let id: String
    public let tasks: [TaskItem]
    public let title: String
    public let minutes: Double
    /// Smallest piece it can be split into.
    public let minPiece: Double
    public let score: Double
    public let must: Bool
    public let errands: Bool
}

/// A placed piece of a chunk on the timeline.
public struct PlanItem: Equatable, Sendable {
    public let chunk: Chunk
    public let start: Double
    public let end: Double
    /// Shrunk to 70% to make the day fit.
    public let squished: Bool
    /// Optional work dropped into a gap.
    public let filler: Bool
    public let part: Int
    public let parts: Int
}

/// A committed chunk that didn't fit, and by how much.
public struct ShortChunk: Equatable, Sendable {
    public let chunk: Chunk
    public let short: Double
}

/// An event laid out on the day: the window, the hard core (arrival, minimum
/// stay and travel), and the squeezable jelly after it.
public struct PlannedEvent: Identifiable, Equatable, Sendable {
    public struct Ghost: Equatable, Sendable {
        public enum Reason: Equatable, Sendable { case work, clash }
        public let reason: Reason
        public let text: String
    }

    public let event: PlannerEvent
    public let winStart: Double
    public let winEnd: Double
    public let arrive: Double
    public let stay: Double
    public let travel: Double
    public let past: Bool
    /// Set when the event can't happen.
    public var ghost: Ghost?
    /// When you leave, after the jelly is squeezed.
    public var leave: Double
    public var squeezed = false

    public var id: String { event.id }
    public var title: String { event.title }
    public var coreStart: Double { arrive - travel }
    public var coreEnd: Double { arrive + stay + travel }
}

public struct DoingBlock: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let title: String
}

/// One day's timeline. Work is a rock, tasks are soft, events are jelly
/// with a hard core, and sleep moves but complains.
public struct DayPlan: Sendable {
    public let day: CalendarDay
    public let isToday: Bool
    /// The current minute, or -1 on other days.
    public let now: Double
    public let wake: Double
    public let bed: Double
    public let hardEnd: Double
    public let dayStart: Double
    public let rocks: [TimeSpan]
    /// Every event that day, including ghosts.
    public let events: [PlannedEvent]
    /// The events that can happen, in the order they were placed.
    public let live: [PlannedEvent]
    public let doing: [DoingBlock]
    public let meal: TimeSpan?
    public let mealMode: DinnerMode
    public let items: [PlanItem]
    public let ghosts: [ShortChunk]
    /// 0 normal, 1 events squeezed, 2 tasks squeezed too.
    public let level: Int
    public let sleepStart: Double
    /// Minutes bedtime got pushed.
    public let push: Double
    /// Free minutes between now (or waking) and bedtime.
    public let free: Double

    public var ghostEvents: [PlannedEvent] {
        events.filter { $0.ghost != nil }
    }
}

public enum DayPlanner {
    /// Stores close, so errands wrap up by 9 PM.
    public static let errandCutoff: Double = 21 * 60

    /// Gaps between `busy` spans inside `from`…`to`.
    public static func freeSlots(_ busy: [TimeSpan], from: Double, to: Double) -> [TimeSpan] {
        let clipped = busy.filter { $0.end > from && $0.start < to }
            .map { TimeSpan(start: max($0.start, from), end: min($0.end, to)) }
            .stableSorted { $0.start < $1.start }
        var out: [TimeSpan] = []
        var cursor = from
        for span in clipped {
            if span.start > cursor { out.append(TimeSpan(start: cursor, end: span.start)) }
            cursor = max(cursor, span.end)
        }
        if cursor < to { out.append(TimeSpan(start: cursor, end: to)) }
        return out
    }

    /// Fills free time with `need` minutes in pieces no smaller than
    /// `minPiece`, earliest first, and marks those pieces busy.
    public static func place(_ busy: inout [TimeSpan], from: Double, to: Double, need: Double,
                             minPiece: Double) -> (pieces: [TimeSpan], left: Double) {
        var pieces: [TimeSpan] = []
        var left = need
        let minPiece = min(minPiece, need)
        for slot in freeSlots(busy, from: from, to: to) {
            if left <= 0 { break }
            var take = min(slot.length, left)
            if left - take > 0 && left - take < minPiece { take = left - minPiece }
            if take < minPiece { continue }
            pieces.append(TimeSpan(start: slot.start, end: slot.start + take))
            left -= take
        }
        busy.append(contentsOf: pieces)
        return (pieces, left)
    }

    /// What's left of `rock` outside `start`…`end`.
    public static func carve(_ rock: TimeSpan, _ start: Double, _ end: Double) -> [TimeSpan] {
        [TimeSpan(start: rock.start, end: min(rock.end, start)), TimeSpan(start: max(rock.start, end), end: rock.end)]
            .filter { $0.length > 0 }
    }
}

extension Engine {
    /// The tasks a day should hold: committed ones get placed first, filler
    /// only goes into gaps.
    public func dayChunks(_ day: CalendarDay, config: DayConfig) -> (committed: [Chunk], filler: [Chunk]) {
        let skip = Set(config.skip), must = Set(config.must)
        let isToday = day == today
        let dayStartDate = day.startDate(calendar: calendar)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStartDate) ?? dayStartDate
        let ref = isToday ? now : day.date(atMinute: Double(state.settings.wake), calendar: calendar)
        let activeIDs = Set(state.active?.taskIDs ?? [])
        let positions = tierPositions()
        let pool = state.activeTasks.filter { task in
            !skip.contains(task.id)
                && !(task.snoozeUntil.map { $0 >= dayEnd } ?? false)
                && !(isToday && activeIDs.contains(task.id))
        }

        func soon(_ task: TaskItem) -> Bool {
            guard let deadline = task.deadline else { return false }
            return daysUntil(deadline, from: ref) <= 2
        }

        var committed: [Chunk] = [], filler: [Chunk] = [], errands: [TaskItem] = []
        for task in pool {
            if task.kind == .errand {
                errands.append(task)
                continue
            }
            let score = scoreTask(task, context: nil, ref: ref, position: positions[task.id]).score
            let minutes: Double
            let minPiece: Double
            if task.kind == .recurring {
                let rem = Double(remaining(task, ref: ref))
                if rem <= 0 { continue }
                minPiece = min(Double(blockSize(task)), rem)
                let perDay = round5(rem / Double(calendar.daysLeftInWeek(ref)))
                minutes = max(minPiece, min(perDay, rem, task.binge ? 120 : Double(sessionCap(task))))
            } else {
                minutes = min(Double(remaining(task)), task.binge ? 120 : Double(sessionCap(task)))
                minPiece = min(minutes, 15)
            }
            let isMust = must.contains(task.id)
            let isCommitted = isMust || task.tier == 1 || soon(task) || (task.kind == .recurring && task.tier <= 2)
            let chunk = Chunk(id: task.id, tasks: [task], title: task.title, minutes: minutes, minPiece: minPiece,
                              score: score + (isMust ? 1000 : 0), must: isMust, errands: false)
            if isCommitted { committed.append(chunk) } else { filler.append(chunk) }
        }

        if errands.count >= 2 {
            let ranked = errands
                .map { (task: $0, score: scoreTask($0, context: nil, ref: ref, position: positions[$0.id]).score) }
                .stableSorted { $0.score > $1.score }
                .prefix(5)
            let minutes = ranked.reduce(10.0) { $0 + Double(errandMinutes($1.task) + 10) }
            let isCommitted = ranked.contains { must.contains($0.task.id) || $0.task.tier == 1 || soon($0.task) }
            let chunk = Chunk(id: "errands", tasks: ranked.map { $0.task }, title: "Errand run: \(ranked.count) stops",
                              minutes: minutes, minPiece: minutes, score: (ranked.map { $0.score }.max() ?? 0) + 15,
                              must: ranked.contains { must.contains($0.task.id) }, errands: true)
            if isCommitted { committed.append(chunk) } else { filler.append(chunk) }
        } else if let task = errands.first {
            let dueSoon = task.deadline.map { daysUntil($0, from: ref) <= 1 } ?? false
            if must.contains(task.id) || dueSoon {
                let minutes = Double(errandMinutes(task) + 20)
                committed.append(Chunk(id: task.id, tasks: [task], title: task.title, minutes: minutes, minPiece: minutes,
                                       score: scoreTask(task, context: nil, ref: ref, position: positions[task.id]).score,
                                       must: must.contains(task.id), errands: true))
            }
        }
        return (committed.stableSorted { $0.score > $1.score }, filler.stableSorted { $0.score > $1.score })
    }

    /// Lays out a day. When it overflows bedtime, relief comes softest
    /// first: squeeze event jelly, then squeeze tasks, then push sleep.
    public func planDay(_ day: CalendarDay) -> DayPlan {
        let settings = state.settings
        let isToday = day == today
        let n = isToday ? nowMinute : -1
        let wake = Double(settings.wake)
        var bed = Double(settings.bed)
        if bed <= wake { bed += 1440 }
        let hardEnd = bed + 180
        let dayStart = isToday ? max(wake, (n / 5).rounded(.up) * 5) : wake
        let config = state.dayConfig(day)

        var events: [PlannedEvent] = state.events.filter { $0.day == day }.map { event in
            let windowStart = Double(event.start)
            var windowEnd = Double(event.end)
            if windowEnd <= windowStart { windowEnd += 1440 }
            let window = windowEnd - windowStart
            let stay = clamp(event.minStay > 0 ? Double(event.minStay) : window, 5, window)
            let arrive = clamp(event.arrive.map { Double($0) } ?? windowStart, windowStart, windowEnd - stay)
            return PlannedEvent(event: event, winStart: windowStart, winEnd: windowEnd, arrive: arrive, stay: stay,
                                travel: max(0, Double(event.travel)), past: isToday && windowEnd <= n,
                                ghost: nil, leave: windowEnd)
        }

        var rocks: [TimeSpan] = []
        if settings.work.on && settings.work.days.contains(day.weekdayIndex(calendar: calendar)) && !config.noWork {
            let start = Double(settings.work.start)
            var end = Double(settings.work.end)
            if end <= start { end += 1440 }
            rocks = [TimeSpan(start: start, end: end)]
            for event in events where event.event.overWork {
                rocks = rocks.flatMap { DayPlanner.carve($0, event.coreStart, event.coreEnd) }
            }
        }

        // Events that can't happen become ghosts. The one you just moved wins.
        let order = Array(events.indices).stableSorted { i, j in
            let a = events[i], b = events[j]
            let aPreferred = a.id == preferredEventID, bPreferred = b.id == preferredEventID
            if aPreferred != bPreferred { return aPreferred }
            return a.arrive < b.arrive
        }
        var liveIndices: [Int] = []
        for i in order {
            let event = events[i]
            if let rock = rocks.first(where: { overlaps(event.coreStart, event.coreEnd, $0.start, $0.end) }) {
                events[i].ghost = .init(reason: .work, text: "Overlaps work, \(formats.range(day, rock.start, rock.end))")
            } else if let other = liveIndices.map({ events[$0] }).first(where: { overlaps(event.coreStart, event.coreEnd, $0.coreStart, $0.coreEnd) }) {
                events[i].ghost = .init(reason: .clash, text: "Clashes with \(other.title)")
            } else {
                liveIndices.append(i)
            }
        }

        var doing: [DoingBlock] = []
        if isToday, let active = state.active {
            let start = (active.startedAt.timeIntervalSince(calendar.startOfDay(for: now)) / 60).rounded()
            doing.append(DoingBlock(start: start, end: max(n, start + Double(active.planned)), title: active.title))
        }

        let mealMode = config.dinner ?? settings.dinner
        let mealMinutes = Double(mealMode.minutes)
        let mealAt = Double(settings.dinnerAt)
        let mealOn = mealMinutes > 0 && !(isToday && n > mealAt + 120)
        let chunks = dayChunks(day, config: config)
        let liveSnapshot = liveIndices.map { events[$0] }

        struct Attempt {
            var busy: [TimeSpan]
            var meal: TimeSpan?
            var items: [PlanItem]
            var ghosts: [ShortChunk]
            var level: Int
            var overflow: Double
        }

        func attempt(_ level: Int) -> Attempt {
            var busy = rocks + doing.map { TimeSpan(start: $0.start, end: $0.end) }
            for event in liveSnapshot {
                busy.append(level == 0 ? TimeSpan(start: event.coreStart, end: event.winEnd + event.travel)
                                       : TimeSpan(start: event.coreStart, end: event.coreEnd))
            }
            var meal: TimeSpan?
            if mealOn {
                let placed = DayPlanner.place(&busy, from: max(dayStart, mealAt), to: hardEnd, need: mealMinutes, minPiece: mealMinutes)
                if placed.left <= 0 { meal = placed.pieces.first }
            }
            var items: [PlanItem] = []
            var ghosts: [ShortChunk] = []
            for chunk in chunks.committed {
                let need = level >= 2 ? max(chunk.minPiece, round5(chunk.minutes * 0.7)) : chunk.minutes
                let limit = chunk.errands ? min(hardEnd, DayPlanner.errandCutoff) : hardEnd
                let placed = DayPlanner.place(&busy, from: dayStart, to: limit, need: need, minPiece: chunk.minPiece)
                for (k, piece) in placed.pieces.enumerated() {
                    items.append(PlanItem(chunk: chunk, start: piece.start, end: piece.end, squished: need < chunk.minutes,
                                          filler: false, part: k + 1, parts: placed.pieces.count))
                }
                if placed.left > 0 { ghosts.append(ShortChunk(chunk: chunk, short: placed.left)) }
            }
            let softEnd = max(0, meal?.end ?? 0, items.map(\.end).max() ?? 0)
            return Attempt(busy: busy, meal: meal, items: items, ghosts: ghosts, level: level, overflow: max(0, softEnd - bed))
        }

        var result = attempt(0)
        if result.overflow > 0 {
            result = attempt(1)
            if result.overflow > 0 { result = attempt(2) }
        }

        // Each live event lasts until the next thing starts, up to its window's end.
        var starts = result.items.map(\.start)
        if let meal = result.meal { starts.append(meal.start) }
        starts += rocks.map(\.start) + liveSnapshot.map(\.coreStart) + doing.map(\.start)
        for i in liveIndices {
            let event = events[i]
            let after = starts.filter { $0 >= event.arrive + event.stay }.min() ?? .infinity
            let leave = clamp(after - event.travel, event.arrive + event.stay, event.winEnd)
            events[i].leave = leave
            events[i].squeezed = leave < event.winEnd - 1
            result.busy.append(TimeSpan(start: event.coreStart, end: leave + event.travel))
        }

        var fills = 0
        for chunk in chunks.filler {
            if fills >= 3 { break }
            let limit = chunk.errands ? min(bed, DayPlanner.errandCutoff) : bed
            let placed = DayPlanner.place(&result.busy, from: dayStart, to: limit, need: chunk.minutes, minPiece: chunk.minPiece)
            if !placed.pieces.isEmpty {
                fills += 1
                for (k, piece) in placed.pieces.enumerated() {
                    result.items.append(PlanItem(chunk: chunk, start: piece.start, end: piece.end, squished: false,
                                                 filler: true, part: k + 1, parts: placed.pieces.count))
                }
            }
        }

        let live = liveIndices.map { events[$0] }
        var ends = [bed] + result.items.filter { !$0.filler }.map(\.end) + [result.meal?.end ?? 0]
        ends += live.map { $0.leave + $0.travel } + doing.map(\.end)
        let sleepStart = min(ends.max() ?? bed, hardEnd)
        let free = DayPlanner.freeSlots(result.busy, from: dayStart, to: bed).reduce(0) { $0 + $1.length }

        return DayPlan(day: day, isToday: isToday, now: n, wake: wake, bed: bed, hardEnd: hardEnd, dayStart: dayStart,
                       rocks: rocks, events: events, live: live, doing: doing, meal: result.meal, mealMode: mealMode,
                       items: result.items.stableSorted { $0.start < $1.start }, ghosts: result.ghosts,
                       level: result.level, sleepStart: sleepStart, push: max(0, sleepStart - bed), free: free)
    }

    /// What Sleep says when bedtime gets pushed.
    public func complaint(push: Double, day: CalendarDay, at minute: Double) -> String {
        if push <= 20 { return "Hey. That’s \(TimeText.duration(push)) of my sleep." }
        if push <= 60 { return "Seriously? Now bedtime is \(formats.time(day, minute))." }
        if push <= 120 { return "Ugh. \(TimeText.duration(push)) late. I’m keeping score." }
        return "This is a cry for help. Bedtime is \(formats.time(day, minute))."
    }
}
