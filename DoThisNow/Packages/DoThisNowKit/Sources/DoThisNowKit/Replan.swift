import Foundation

/// Catching up on a day: blocks you placed earlier today that ended without
/// being done move into the open gaps later today. What doesn't fit goes to
/// tomorrow's first gap, back to the Inbox, or gets let go.
public struct Replan: Equatable, Sendable {
    /// A missed block that fits later today.
    public struct Move: Equatable, Sendable {
        public let id: String
        public let title: String
        public let from: Int
        public let to: Int
    }

    /// A missed block with no room left today.
    public struct Overflow: Equatable, Sendable {
        public let id: String
        public let title: String
        public let minutes: Int
        /// Tomorrow's first gap that fits it, or nil when tomorrow is full too.
        public let tomorrow: Int?
    }

    public var moves: [Move]
    public var overflow: [Overflow]

    public var isEmpty: Bool {
        moves.isEmpty && overflow.isEmpty
    }
}

/// What to do with a missed block that doesn't fit today.
public enum Leftover: String, CaseIterable, Sendable {
    case tomorrow, inbox, letGo

    public var label: String {
        switch self {
        case .tomorrow: return "Tomorrow"
        case .inbox: return "Back to the Inbox"
        case .letGo: return "Let it go"
        }
    }
}

extension Engine {
    /// The first starts on `day` with `minutes` free, on the five-minute
    /// mark, after now on today. `alsoBusy` holds time already promised.
    /// With meetings brought in from a locked calendar, work hours are open
    /// for your own tasks and only the meetings themselves are off limits.
    public func openSlots(on day: CalendarDay, minutes: Int, limit: Int = 4, alsoBusy: [TimeSpan] = []) -> [Int] {
        let plan = planDay(day)
        var busy = state.meetingSettings.on ? plan.locked : plan.rocks
        busy += plan.blocks.map { TimeSpan(start: Double($0.start), end: Double($0.end)) }
        busy += plan.live.map { TimeSpan(start: $0.coreStart, end: $0.leave + $0.travel) }
        busy += plan.doing.map { TimeSpan(start: $0.start, end: $0.end) }
        if let meal = plan.meal { busy.append(meal) }
        busy += alsoBusy
        var starts: [Int] = []
        for slot in DayPlanner.freeSlots(busy, from: plan.dayStart, to: plan.bed) {
            let start = (slot.start / 5).rounded(.up) * 5
            guard slot.end - start >= Double(minutes) else { continue }
            starts.append(Int(start))
            if starts.count == limit { break }
        }
        return starts
    }

    /// Blocks on today that ended without being done or started, earliest first.
    public var missedBlocks: [TimeBlock] {
        let n = nowMinute
        let underway = state.active?.blockID
        return state.blocks
            .filter { $0.day == today && !$0.done && Double($0.end) <= n && $0.id != underway }
            .stableSorted { $0.start < $1.start }
    }

    /// Where each missed block would go. Nothing changes until you apply it.
    public func replan() -> Replan {
        var later: [TimeSpan] = []
        var nextDay: [TimeSpan] = []
        var moves: [Replan.Move] = []
        var overflow: [Replan.Overflow] = []
        let tomorrow = today.adding(days: 1, calendar: calendar)
        for block in missedBlocks {
            if let start = openSlots(on: today, minutes: block.minutes, limit: 1, alsoBusy: later).first {
                later.append(TimeSpan(start: Double(start), end: Double(start + block.minutes)))
                moves.append(Replan.Move(id: block.id, title: block.title, from: block.start, to: start))
            } else {
                let start = openSlots(on: tomorrow, minutes: block.minutes, limit: 1, alsoBusy: nextDay).first
                if let start { nextDay.append(TimeSpan(start: Double(start), end: Double(start + block.minutes))) }
                overflow.append(Replan.Overflow(id: block.id, title: block.title, minutes: block.minutes, tomorrow: start))
            }
        }
        return Replan(moves: moves, overflow: overflow)
    }
}

extension PlannerState {
    /// Carries out a replan. `leftovers` says what happens to each block that
    /// didn't fit today; tomorrow is the default, and the Inbox when tomorrow is full.
    public mutating func apply(_ replan: Replan, leftovers: [String: Leftover], today: CalendarDay,
                               now: Date, calendar: Calendar) {
        for move in replan.moves {
            updateBlock(move.id) { $0.start = move.to }
        }
        let tomorrow = today.adding(days: 1, calendar: calendar)
        for item in replan.overflow {
            guard let missed = block(item.id) else { continue }
            var choice = leftovers[item.id] ?? .tomorrow
            if choice == .tomorrow && item.tomorrow == nil { choice = .inbox }
            switch choice {
            case .tomorrow:
                updateBlock(item.id) { b in
                    b.day = tomorrow
                    b.start = item.tomorrow ?? b.start
                }
            case .inbox:
                blocks.removeAll { $0.id == item.id }
            case .letGo:
                blocks.removeAll { $0.id == item.id }
                switch missed.ref.source {
                case .app:
                    letGo(missed.ref.id, now: now)
                default:
                    if !inbox.hidden.contains(missed.ref.key) { inbox.hidden.append(missed.ref.key) }
                }
            }
        }
    }
}
