import SwiftUI
import DoThisNowKit

/// A check-in about a stalled task, with its two or three answers.
struct NudgeCard: View {
    @Environment(AppModel.self) private var model
    let nudge: Nudge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHECK-IN")
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.accent)
            Text(nudge.text)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            if let ask = nudge.ask {
                Text(ask)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
            }
            FlowLayout {
                buttons
            }
            .padding(.top, 2)
        }
        .card()
    }

    @ViewBuilder
    private var buttons: some View {
        let id = nudge.task.id
        switch nudge.kind {
        case .loosen:
            let suggest = nudge.suggest ?? nudge.task.weekly
            Button("Loosen to \(TimeText.duration(suggest)) a week") { model.loosen(id, to: suggest) }
                .buttonStyle(.dtn(.primary, size: .small))
            Button("I’m serious, keep it") { model.keepGoal(id) }
                .buttonStyle(.dtn(size: .small))
            Button("Let it go") { model.letGo(id) }
                .buttonStyle(.dtn(size: .small))
        case .serious:
            Button("Yes, push me on it") { model.nudgeSerious(id) }
                .buttonStyle(.dtn(.primary, size: .small))
            Button("Lower its priority") { model.nudgeLower(id) }
                .buttonStyle(.dtn(size: .small))
            Button("Let it go") { model.letGo(id) }
                .buttonStyle(.dtn(size: .small))
        case .remind:
            Button("Do it now") { model.forcePick(id) }
                .buttonStyle(.dtn(.primary, size: .small))
            Button("Remind me next week") { model.remindNextWeek(id) }
                .buttonStyle(.dtn(size: .small))
        }
    }
}

/// A snoozed task whose time has come.
struct ReminderCard: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REMINDER")
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.accent)
            Text("You asked me to bring back “\(task.title)”.")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            FlowLayout {
                Button("Do it now") { model.remindGo(task.id) }
                    .buttonStyle(.dtn(.primary, size: .small))
                Button("Got it") { model.remindDismiss(task.id) }
                    .buttonStyle(.dtn(size: .small))
            }
        }
        .card()
    }
}

/// "Leave now" or "you planned to be there until…".
struct EventNowBanner: View {
    @Environment(AppModel.self) private var model
    let event: PlannedEvent
    let leaveNow: Bool

    var body: some View {
        let day = model.today
        let message = leaveNow
            ? "leave now to get there by \(model.formats.time(day, event.arrive))."
            : "you planned to be there until at least \(model.formats.time(day, event.arrive + event.stay))."
        VStack(alignment: .leading, spacing: 10) {
            (Text(event.title).bold() + Text(": \(message) Running late or skipping it? Move your arrival on the Day view and see what it bumps."))
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            Button("Open my day") { model.tab = .day }
                .buttonStyle(.dtn(size: .small))
        }
        .banner()
    }
}
