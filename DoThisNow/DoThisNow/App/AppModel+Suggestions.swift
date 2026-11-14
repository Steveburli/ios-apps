import Foundation
import DoThisNowKit

/// Moving the tasks the planner suggests for the gaps. A suggestion you move
/// becomes a block you placed yourself, so it stays where you put it and the
/// planner stops suggesting that task elsewhere on the day.
extension AppModel {
    /// Only single-task suggestions can move; an errand run is several tasks.
    func canMoveSuggestion(_ chunk: Chunk) -> Bool {
        chunk.tasks.count == 1 && !chunk.errands
    }

    /// Turns suggestion `chunkID` into a block at `minute` on the day shown,
    /// bumping whatever it lands on. Returns the new block's id.
    @discardableResult
    func pinSuggestion(_ chunkID: String, at minute: Int, quiet: Bool = false) -> String? {
        let day = dayShown
        let plan = engine.planDay(day)
        guard let chunk = chunk(chunkID, in: plan), canMoveSuggestion(chunk), let task = chunk.tasks.first else { return nil }
        let before = plan.push
        let block = TimeBlock(ref: SourceRef(.app, task.id), title: task.title, day: day, start: max(0, minute),
                              minutes: Int(chunk.minutes.rounded()))
        state.blocks.append(block)
        state.blocks = reflowed(state.blocks, moving: block.id, to: block.start, day: day)
        sheet = nil
        commit()
        if !quiet {
            let start = state.block(block.id)?.start ?? block.start
            show("“\(block.title)” moved to \(formats.time(day, Double(start))). It stays there now.")
        }
        let after = engine.planDay(day).push
        if after > before + 4 && state.settings.sound { Sounds.groan(push: after) }
        return block.id
    }

    /// The end of a long-press drag on a suggestion. Dropped on the iPad's
    /// left column, it comes off the day instead.
    func dropSuggestion(_ chunkID: String, from start: Double, by points: CGFloat, pointsPerMinute: CGFloat) {
        if blockOverSideList {
            blockOverSideList = false
            skipForDay(chunkID)
            return
        }
        let minute = max(0, Reflow.snap(start + Double(points / pointsPerMinute)))
        guard minute != Reflow.snap(start) else { return }
        pinSuggestion(chunkID, at: minute)
    }

    /// VoiceOver's swipe up and down on a suggestion: pins it five minutes over.
    func nudgeSuggestion(_ chunkID: String, from start: Double, by minutes: Int) {
        pinSuggestion(chunkID, at: Reflow.snap(start) + minutes, quiet: true)
    }

    /// Other tasks that could take a suggestion's place: the day's other
    /// suggestions first, then the rest of your list.
    func swapCandidates(for chunkID: String, in plan: DayPlan) -> [TaskItem] {
        guard let chunk = chunk(chunkID, in: plan) else { return [] }
        var seen = Set(chunk.tasks.map(\.id))
        seen.formUnion(state.blocks.filter { $0.day == plan.day && $0.ref.source == .app }.map(\.ref.id))
        seen.formUnion(state.dayConfig(plan.day).skip)
        var out: [TaskItem] = []
        let planned = plan.items.map(\.chunk) + plan.ghosts.map(\.chunk)
        for task in planned.filter({ $0.tasks.count == 1 }).flatMap(\.tasks) + state.activeTasks where !seen.contains(task.id) {
            seen.insert(task.id)
            out.append(task)
        }
        return Array(out.prefix(12))
    }

    /// Puts `taskID` where suggestion `chunkID` was, as a block you placed.
    /// The old suggestion stays soft and finds another gap.
    func swapSuggestion(_ chunkID: String, for taskID: String, at minute: Int, minutes: Int) {
        let day = dayShown
        guard let task = state.task(taskID) else { return }
        let old = chunk(chunkID, in: engine.planDay(day))?.title
        let block = TimeBlock(ref: SourceRef(.app, task.id), title: task.title, day: day, start: max(0, minute),
                              minutes: max(5, minutes))
        state.blocks.append(block)
        state.blocks = reflowed(state.blocks, moving: block.id, to: block.start, day: day)
        sheet = nil
        commit()
        show("“\(task.title)” is there now" + (old.map { ". “\($0)” will find another gap." } ?? "."))
    }
}
