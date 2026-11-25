import Foundation

/// One kid's totals for one day, for the Today tab's summary row.
public struct DaySummary: Equatable {
    public var bottles = 0
    public var bottleOz: Double = 0
    public var nursing = 0
    public var nursingMinutes = 0
    public var diapers = 0
    public var wet = 0
    public var dirty = 0
    public var sleepMinutes = 0
    public var naps = 0
    public var meals = 0
    public var foods = 0
    public var pottySuccesses = 0
    public var accidents = 0

    public init() {}
}

public enum Summary {
    /// Totals for the day `date` falls on. A sleep that crosses midnight counts
    /// only the minutes inside the day; a running one counts up to `now`.
    public static func day(_ logs: [LogEntry], kidID: String, on date: Date, now: Date,
                           calendar: Calendar = Dates.calendar) -> DaySummary {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return DaySummary() }
        var summary = DaySummary()
        var foodIDs = Set<String>()
        for entry in logs where entry.kidID == kidID {
            if entry.kind == .sleep {
                let end = entry.end ?? now
                let overlap = min(end, dayEnd).timeIntervalSince(max(entry.start, dayStart))
                if overlap > 0 {
                    summary.sleepMinutes += Int(overlap / 60)
                    if entry.start >= dayStart { summary.naps += 1 }
                }
                continue
            }
            guard entry.start >= dayStart, entry.start < dayEnd else { continue }
            switch entry.kind {
            case .bottle:
                summary.bottles += 1
                summary.bottleOz += entry.amountOz ?? 0
            case .nursing:
                summary.nursing += 1
                summary.nursingMinutes += Int(entry.duration(now: now) / 60)
            case .diaper:
                summary.diapers += 1
                if entry.diaper?.isWet == true { summary.wet += 1 }
                if entry.diaper?.isDirty == true { summary.dirty += 1 }
            case .solids:
                summary.meals += 1
                for bite in entry.bites { foodIDs.insert(bite.foodID) }
            case .potty:
                if entry.potty?.isSuccess == true { summary.pottySuccesses += 1 }
                if entry.potty == .accident { summary.accidents += 1 }
            default:
                break
            }
        }
        summary.foods = foodIDs.count
        return summary
    }

    /// The newest entry of any of these kinds.
    public static func last(_ logs: [LogEntry], kidID: String, kinds: Set<LogKind>) -> LogEntry? {
        logs.filter { $0.kidID == kidID && kinds.contains($0.kind) }.max { $0.start < $1.start }
    }

    /// Timers still running for a kid (a nap, a nursing session).
    public static func running(_ logs: [LogEntry], kidID: String) -> [LogEntry] {
        logs.filter { $0.kidID == kidID && $0.isRunning }.sorted { $0.start < $1.start }
    }

    /// The typical time between feeds: the median gap between the last
    /// `sample` feeds in the past two days. Nil with fewer than three feeds.
    public static func feedGap(_ logs: [LogEntry], kidID: String, now: Date, sample: Int = 8) -> TimeInterval? {
        let since = now.addingTimeInterval(-48 * 3600)
        let starts = logs
            .filter { $0.kidID == kidID && $0.kind.isFeed && $0.start >= since && $0.start <= now }
            .map { $0.start }
            .sorted()
            .suffix(sample)
        guard starts.count >= 3 else { return nil }
        let list = Array(starts)
        var gaps: [TimeInterval] = []
        for index in 1..<list.count {
            let gap = list[index].timeIntervalSince(list[index - 1])
            // Skip a long overnight stretch and double taps.
            if gap >= 20 * 60 && gap <= 8 * 3600 { gaps.append(gap) }
        }
        guard !gaps.isEmpty else { return nil }
        gaps.sort()
        let middle = gaps.count / 2
        return gaps.count % 2 == 1 ? gaps[middle] : (gaps[middle - 1] + gaps[middle]) / 2
    }

    /// When the next feed is likely: the last feed plus the typical gap.
    public static func nextFeed(_ logs: [LogEntry], kidID: String, now: Date) -> Date? {
        guard let gap = feedGap(logs, kidID: kidID, now: now),
              let last = Summary.last(logs, kidID: kidID, kinds: [.bottle, .nursing]) else { return nil }
        return last.start.addingTimeInterval(gap)
    }

    /// Which side to start on next time: the other side from the last nursing.
    public static func nextSide(_ logs: [LogEntry], kidID: String) -> Side {
        guard let last = Summary.last(logs, kidID: kidID, kinds: [.nursing]), let side = last.side else { return .left }
        switch side {
        case .left: return .right
        case .right: return .left
        case .both: return .left
        }
    }

    /// One kid's entries on one day, newest first, for the timeline.
    public static func timeline(_ logs: [LogEntry], kidID: String, on date: Date,
                                calendar: Calendar = Dates.calendar) -> [LogEntry] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return logs
            .filter { entry in
                guard entry.kidID == kidID else { return false }
                if entry.start >= dayStart && entry.start < dayEnd { return true }
                // A sleep that started yesterday and ran into today.
                if entry.kind == .sleep, entry.start < dayStart, (entry.end ?? dayEnd) > dayStart { return true }
                return false
            }
            .sorted { $0.start > $1.start }
    }

    /// Growth entries, oldest first, for the Grow tab's chart.
    public static func growth(_ logs: [LogEntry], kidID: String) -> [LogEntry] {
        logs.filter { $0.kidID == kidID && $0.kind == .growth }.sorted { $0.start < $1.start }
    }

    /// Which quick-log buttons to show first, by age. A baby leads with
    /// bottles and diapers; a preschooler leads with potty and meals.
    public static func quickKinds(ageMonths: Int) -> [LogKind] {
        if ageMonths < 6 {
            return [.bottle, .nursing, .diaper, .sleep, .pump, .meds, .temperature, .bath, .growth, .note]
        }
        if ageMonths < 18 {
            return [.bottle, .solids, .diaper, .sleep, .nursing, .meds, .temperature, .bath, .growth, .note]
        }
        if ageMonths < 30 {
            return [.solids, .diaper, .sleep, .potty, .bottle, .meds, .temperature, .bath, .growth, .note]
        }
        return [.solids, .potty, .sleep, .meds, .temperature, .bath, .growth, .note, .diaper]
    }
}
