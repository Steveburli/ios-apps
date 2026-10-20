import SwiftUI
import DoThisNowKit

/// What you can do with a task block on the Day view.
struct DayItemSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let chunkID: String

    var body: some View {
        let plan = model.engine.planDay(model.dayShown)
        let pieces = plan.items.filter { $0.chunk.id == chunkID }
        NavigationStack {
            Group {
                if let chunk = model.chunk(chunkID, in: plan) {
                    content(chunk, plan: plan, pieces: pieces)
                } else {
                    ContentUnavailableView("This changed", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("It’s no longer on this day’s plan."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func content(_ chunk: Chunk, plan: DayPlan, pieces: [PlanItem]) -> some View {
        let f = model.formats
        let config = model.state.dayConfig(plan.day)
        let ids = chunk.tasks.map(\.id)
        let isMust = ids.contains { config.must.contains($0) }
        var when = pieces.isEmpty ? "Doesn’t fit" : pieces.map { f.range(plan.day, $0.start, $0.end) }.joined(separator: ", ")
        if pieces.contains(where: \.filler) { when += " · filling a gap" }
        if pieces.contains(where: \.squished) { when += " · squeezed to fit" }
        let which = plan.isToday ? "today" : "this day"

        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chunk.title)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.ink)
                    Text(when)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                }
                if chunk.tasks.count > 1 {
                    ForEach(chunk.tasks) { task in
                        HStack {
                            Text(task.title) + Text(task.place.isEmpty ? "" : " · \(task.place)").foregroundStyle(Theme.ink3)
                            Spacer()
                            Text(TimeText.duration(task.estimate > 0 ? task.estimate : 15))
                                .foregroundStyle(Theme.ink3)
                        }
                        .font(.subheadline)
                    }
                }
            }
            Section {
                if plan.isToday {
                    option("Start it now", detail: "Runs a \(TimeText.duration(chunk.minutes)) timer") {
                        model.startFromDay(chunkID)
                    }
                }
                option(isMust ? "Remove from must-do" : "Must do \(which)",
                       detail: isMust ? "Let it flow like everything else" : "It goes first, even if bedtime gets pushed",
                       selected: isMust) {
                    model.toggleMust(chunkID)
                }
                option("Not \(which)", detail: "Take it off this day’s plan") {
                    model.skipForDay(chunkID)
                }
                if chunk.tasks.count == 1, let id = ids.first {
                    option("Edit task", detail: nil) {
                        model.sheet = .editTask(id)
                    }
                }
            }
        }
    }

    private func option(_ title: String, detail: String?, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.bold)).foregroundStyle(Theme.ink)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(Theme.ink3)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Dinner can shrink when the day gets tight.
struct MealSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let current = model.state.dayConfig(model.dayShown).dinner ?? model.state.settings.dinner
        let which = model.dayShown == model.today ? "today" : "this day"
        NavigationStack {
            List {
                Section {
                    ForEach(DinnerMode.allCases, id: \.self) { mode in
                        Button { model.setDinner(mode) } label: {
                            HStack {
                                Text(mode.label).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(mode.minutes > 0 ? TimeText.duration(mode.minutes) : "no block")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.ink3)
                                if mode == current {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .accessibilityAddTraits(mode == current ? .isSelected : [])
                    }
                } footer: {
                    Text("This changes \(which) only.")
                }
            }
            .navigationTitle("Dinner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
