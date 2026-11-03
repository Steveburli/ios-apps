import SwiftUI
import DoThisNowKit

/// Replan: blocks from earlier today that ended undone move into the gaps
/// later today. You see a preview first, and Undo puts the day back.
extension AppModel {
    /// Blocks from earlier today that ended without being done.
    var missedCount: Int {
        engine.missedBlocks.count
    }

    func openReplan() {
        dayShown = today
        sheet = .replan
    }

    func applyReplan(_ replan: Replan, leftovers: [String: Leftover]) {
        guard !replan.isEmpty else { return }
        replanUndo = ReplanUndo(blocks: state.blocks, tasks: state.tasks, hidden: state.inbox.hidden,
                                count: replan.moves.count + replan.overflow.count)
        state.apply(replan, leftovers: leftovers, today: today, now: Date(), calendar: calendar)
        sheet = nil
        dayShown = today
        dayPage = .timeline
        scrollDayToNow = true
        commit()
        show(replan.overflow.isEmpty
             ? "Moved \(replan.moves.count) to later today"
             : "Moved \(replan.moves.count) to later today. \(replan.overflow.count) went elsewhere")
    }

    func undoReplan() {
        guard let undo = replanUndo else { return }
        state.blocks = undo.blocks
        state.tasks = undo.tasks
        state.inbox.hidden = undo.hidden
        replanUndo = nil
        commit()
        show("Your day is back the way it was")
    }

    func dismissReplanUndo() {
        replanUndo = nil
    }
}
