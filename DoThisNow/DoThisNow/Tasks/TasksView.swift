import SwiftUI
import DoThisNowKit

/// Priorities: four tiers you drag tasks between.
struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var editMode: EditMode = .inactive

    /// The tier headers and tasks as one list, so a task can be dragged
    /// across tiers. A task's tier is the header above it.
    private enum Row: Identifiable {
        case header(Int, count: Int)
        case task(TaskItem)

        var id: String {
            switch self {
            case .header(let tier, _): return "tier-\(tier)"
            case .task(let task): return task.id
            }
        }
    }

    private var rows: [Row] {
        let active = model.state.activeTasks
        return Tier.all.flatMap { tier -> [Row] in
            let tasks = active.filter { $0.tier == tier }
            return [Row.header(tier, count: tasks.count)] + tasks.map { Row.task($0) }
        }
    }

    var body: some View {
        let engine = model.engine
        let active = model.state.activeTasks
        let finished = model.state.tasks.filter { !$0.isActive }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Priorities")
                            .font(Theme.display(36))
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("+ Add") { model.sheet = .newTask }
                            .buttonStyle(.dtn(.primary))
                    }
                    Text("Drag to reorder (tap Reorder, or touch and hold a task). Higher levels win. Within a level, approaching deadlines and things you haven’t done in a while come up first.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                }
                .plainRow()

                if model.state.hasExamples {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("You’re looking at example tasks. Play with them, then clear them out when you’re ready to add your own.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Button("Remove examples") { model.removeExamples() }
                            .buttonStyle(.dtn(size: .small))
                    }
                    .banner()
                    .plainRow()
                }

                ForEach(engine.nudges().prefix(3)) { nudge in
                    NudgeCard(nudge: nudge)
                        .plainRow()
                }

                if active.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Nothing here yet. Add the things you want to get done, and I’ll figure out the order with you.")
                            .foregroundStyle(Theme.ink)
                        FlowLayout {
                            Button("Add a task") { model.sheet = .newTask }
                                .buttonStyle(.dtn(.primary))
                            if !model.state.hasExamples {
                                Button("Load example tasks") { model.loadExamples() }
                                    .buttonStyle(.dtn())
                            }
                        }
                    }
                    .card()
                    .plainRow()
                }
            }

            Section {
                ForEach(rows) { row in
                    switch row {
                    case .header(let tier, let count):
                        TierHeader(tier: tier, count: count)
                            .plainRow(top: 14)
                            .moveDisabled(true)
                    case .task(let task):
                        TaskRow(task: task)
                            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .onMove(perform: move)
            }

            if !finished.isEmpty {
                Section {
                    DisclosureGroup("Done and let go (\(finished.count))") {
                        ForEach(finished.prefix(40)) { task in
                            HStack(spacing: 10) {
                                Text(task.title)
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.ink2)
                                Spacer()
                                Text(task.archived ? "Let go" : "Done \(task.doneAt.map { model.formats.shortDate($0) } ?? "")")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.ink2)
                                Button("Restore") { model.restore(task.id) }
                                    .buttonStyle(.dtn(size: .small))
                            }
                            .font(.subheadline)
                        }
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.ink2)
                    .tint(Theme.ink2)
                    .plainRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !active.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = rows
        reordered.move(fromOffsets: source, toOffset: destination)
        var tier = 1
        var order: [(id: String, tier: Int)] = []
        for row in reordered {
            switch row {
            case .header(let t, _): tier = t
            case .task(let task): order.append((task.id, tier))
            }
        }
        model.applyOrder(order)
    }
}

private struct TierHeader: View {
    let tier: Int
    let count: Int

    private var blurb: String? {
        switch tier {
        case 1: return "Always considered first"
        case 4: return "When nothing else fits"
        default: return nil
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Tier.name(tier).uppercased())
                .font(.footnote.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.ink2)
            Text("\(count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.ink3)
            if let blurb {
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
            if count == 0 {
                Spacer()
                Text("Drag tasks here")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Button {
            model.sheet = .editTask(task.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                FlowLayout(spacing: 6) {
                    meta
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if task.kind != .recurring {
                Button("Done") { model.markTaskDone(task.id) }
                    .tint(Theme.good)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Let go") { model.letGo(task.id) }
                .tint(Theme.ink3)
        }
        .contextMenu {
            ForEach(Tier.all, id: \.self) { tier in
                if tier != task.tier {
                    Button("Move to \(Tier.name(tier))") { model.moveTask(task.id, toTier: tier) }
                }
            }
        }
    }

    @ViewBuilder
    private var meta: some View {
        let engine = model.engine
        if task.kind == .recurring {
            let done = engine.weekMinutes(task.id)
            let goal = task.weekly > 0 ? task.weekly : 60
            HStack(spacing: 6) {
                Capsule()
                    .fill(Theme.surface2)
                    .frame(width: 72, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.good).frame(width: 72 * min(1, CGFloat(done) / CGFloat(goal)), height: 6)
                    }
                Text("\(TimeText.duration(done)) of \(TimeText.duration(goal)) this week")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
        }
        if task.kind == .errand {
            Tag(text: task.place.isEmpty ? "Errand" : "Errand · \(task.place)")
        }
        if let deadline = task.deadline {
            let days = model.today.days(until: deadline, calendar: model.calendar)
            Tag(text: engine.deadlineLabel(deadline) + (task.stakes >= 7 ? " · high stakes" : ""),
                tone: days < 0 ? .bad : days <= 2 ? .warn : .plain)
        }
        if task.kind != .errand {
            Text((task.places.isEmpty ? [.anywhere] : task.places).map(\.shortLabel).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.ink3)
        }
        if task.kind != .recurring {
            Text(task.spent > 0 ? "\(TimeText.duration(engine.remaining(task))) left" : "~\(TimeText.duration(task.estimate))")
                .font(.caption)
                .foregroundStyle(Theme.ink3)
        }
        if let until = task.snoozeUntil, until > model.now {
            Tag(text: "Snoozed till " + model.formats.when(until, now: model.now).replacingOccurrences(of: "at ", with: "", options: .anchored))
        }
        if task.isExample {
            Tag(text: "Example", tone: .example)
        }
    }
}

extension View {
    /// A list row with no background, separator or extra inset.
    func plainRow(top: CGFloat = 6) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
