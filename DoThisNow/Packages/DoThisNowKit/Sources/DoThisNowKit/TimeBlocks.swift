import Foundation

/// Where a task in the Inbox comes from.
public enum TaskSource: String, Codable, CaseIterable, Sendable {
    /// Do This Now's own task list.
    case app
    /// Apple Reminders.
    case reminders
    /// Google Tasks.
    case google
    /// Typed into the Inbox, or sent by Shortcuts or the Share button.
    case inbox

    public var label: String {
        switch self {
        case .app: return "Do This Now"
        case .reminders: return "Reminders"
        case .google: return "Google Tasks"
        case .inbox: return "Inbox"
        }
    }
}

/// Points at one task in one source. `key` stays the same across launches.
public struct SourceRef: Codable, Hashable, Sendable {
    public var source: TaskSource
    public var id: String

    public init(_ source: TaskSource, _ id: String) {
        self.source = source
        self.id = id
    }

    public var key: String {
        source.rawValue + ":" + id
    }
}

/// A task you put on a day yourself. Blocks never overlap: moving one bumps
/// the others out of its way.
public struct TimeBlock: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var ref: SourceRef
    public var title: String
    public var day: CalendarDay
    /// Minutes after midnight.
    public var start: Int
    public var minutes: Int
    public var done = false
    public var isExample = false

    public init(id: String = newID(), ref: SourceRef, title: String, day: CalendarDay, start: Int, minutes: Int) {
        self.id = id
        self.ref = ref
        self.title = title
        self.day = day
        self.start = start
        self.minutes = max(1, minutes)
    }

    public var end: Int {
        start + minutes
    }

    private enum CodingKeys: String, CodingKey { case id, ref, title, day, start, minutes, done, isExample }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  ref: try c.decode(SourceRef.self, forKey: .ref),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  day: try c.decode(CalendarDay.self, forKey: .day),
                  start: try c.decodeIfPresent(Int.self, forKey: .start) ?? 9 * 60,
                  minutes: try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 30)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
    }
}

public enum Reflow {
    /// Puts block `id` at `start` and moves the blocks it lands on out of
    /// the way, so no two blocks overlap.
    ///
    /// A block that sat mostly above the new spot slides up to end where the
    /// moved block starts, if that keeps it after `earliest`; otherwise it
    /// goes below. Everything else slides down. The push carries on from
    /// block to block, and a pushed block hops over `obstacles` (event cores,
    /// blocks already under way). Blocks that aren't in the way stay put.
    public static func move(_ id: String, to start: Int, in blocks: [TimeBlock], obstacles: [TimeSpan] = [],
                            earliest: Int = 0) -> [TimeBlock] {
        guard var moved = blocks.first(where: { $0.id == id }) else { return blocks }
        moved.start = max(0, start)
        let middle = Double(moved.start) + Double(moved.minutes) / 2
        let others = blocks.filter { $0.id != id }
        let above = others.filter { Double($0.start) + Double($0.minutes) / 2 < middle }
        let aboveIDs = Set(above.map(\.id))
        var below = others.filter { !aboveIDs.contains($0.id) }

        var placed: [String: TimeBlock] = [moved.id: moved]

        // Upward, nearest first.
        var ceiling = moved.start
        for original in above.stableSorted(by: { $0.end > $1.end }) {
            var block = original
            if block.end > ceiling {
                block.start = ceiling - block.minutes
                block.start = hopUp(block, obstacles)
                if block.start < earliest {
                    below.append(original)
                    continue
                }
            }
            placed[block.id] = block
            ceiling = min(ceiling, block.start)
        }

        // Downward, in time order.
        var floor = moved.end
        for original in below.stableSorted(by: { $0.start < $1.start }) {
            var block = original
            if block.start < floor {
                block.start = floor
                block.start = hopDown(block, obstacles)
            }
            placed[block.id] = block
            floor = max(floor, block.end)
        }

        return blocks.map { placed[$0.id] ?? $0 }
    }

    /// The latest start at or before the block's own that misses every obstacle.
    static func hopUp(_ block: TimeBlock, _ obstacles: [TimeSpan]) -> Int {
        var start = block.start
        while let hit = obstacles.first(where: { overlaps(Double(start), Double(start + block.minutes), $0.start, $0.end) }) {
            start = Int(hit.start.rounded(.down)) - block.minutes
        }
        return start
    }

    /// The earliest start at or after the block's own that misses every obstacle.
    static func hopDown(_ block: TimeBlock, _ obstacles: [TimeSpan]) -> Int {
        var start = block.start
        while let hit = obstacles.first(where: { overlaps(Double(start), Double(start + block.minutes), $0.start, $0.end) }) {
            start = Int(hit.end.rounded(.up))
        }
        return start
    }

    /// Rounds a minute to the nearest five, for dragging.
    public static func snap(_ minute: Double) -> Int {
        Int((minute / 5).rounded()) * 5
    }
}

extension PlannerState {
    public func block(_ id: String) -> TimeBlock? {
        blocks.first { $0.id == id }
    }

    public mutating func updateBlock(_ id: String, _ change: (inout TimeBlock) -> Void) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            change(&blocks[index])
        }
    }

    /// Blocks still waiting for a task, from `day` on. A task with one of
    /// these is already planned, so the Inbox leaves it out.
    public func plannedKeys(from day: CalendarDay) -> Set<String> {
        Set(blocks.filter { !$0.done && $0.day >= day }.map(\.ref.key))
    }
}
