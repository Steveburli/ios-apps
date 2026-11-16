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
                if model.canMoveSuggestion(chunk) {
                    NavigationLink {
                        MoveSuggestionView(chunk: chunk, from: pieces.first?.start)
                    } label: {
                        optionLabel("Move to…", detail: "Pick a time. It stays there after that")
                    }
                }
                if let piece = pieces.first {
                    NavigationLink {
                        SwapSuggestionView(chunkID: chunkID, start: Reflow.snap(piece.start),
                                           minutes: Int((piece.end - piece.start).rounded()))
                    } label: {
                        optionLabel("Swap for something else", detail: "Put a different task at \(f.time(plan.day, piece.start))")
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
                optionLabel(title, detail: detail)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func optionLabel(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.bold)).foregroundStyle(Theme.ink)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Theme.ink3)
            }
        }
    }
}

/// "Move to…" for a suggested task: the next open gaps, or any time you pick.
/// Either way it becomes a block you placed, so it stays put.
private struct MoveSuggestionView: View {
    @Environment(AppModel.self) private var model
    let chunk: Chunk
    let from: Double?
    @State private var time = Date()

    var body: some View {
        let day = model.dayShown
        let f = model.formats
        let gaps = model.openSlots(on: day, minutes: Int(chunk.minutes.rounded()))
        List {
            if !gaps.isEmpty {
                Section("Open gaps") {
                    ForEach(gaps, id: \.self) { start in
                        Button(f.range(day, Double(start), Double(start) + chunk.minutes)) {
                            model.pinSuggestion(chunk.id, at: start)
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
            }
            Section {
                DatePicker("Start at", selection: $time, displayedComponents: .hourAndMinute)
                Button("Put it here") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                    let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    model.pinSuggestion(chunk.id, at: Reflow.snap(Double(minute)))
                }
                .font(.body.weight(.bold))
            } header: {
                Text("Any time")
            } footer: {
                Text("Anything it lands on moves out of the way.")
            }
        }
        .navigationTitle("Move “\(chunk.title)”")
        .onAppear {
            let minute = Int(from ?? Double(model.state.settings.wake))
            time = Calendar.current.date(bySettingHour: min(23, minute / 60), minute: minute % 60, second: 0, of: Date()) ?? Date()
        }
    }
}

/// "Swap for something else": pick another task to put in this suggestion's slot.
private struct SwapSuggestionView: View {
    @Environment(AppModel.self) private var model
    let chunkID: String
    let start: Int
    let minutes: Int

    var body: some View {
        let plan = model.engine.planDay(model.dayShown)
        let candidates = model.swapCandidates(for: chunkID, in: plan)
        List {
            if candidates.isEmpty {
                Text("Nothing else on your list to swap in.")
                    .foregroundStyle(Theme.ink3)
            } else {
                Section {
                    ForEach(candidates) { task in
                        Button {
                            model.swapSuggestion(chunkID, for: task.id, at: start, minutes: minutes)
                        } label: {
                            HStack {
                                Text(task.title).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(TimeText.duration(task.estimate > 0 ? task.estimate : 15))
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                    }
                } footer: {
                    Text("The one you swap in stays at \(model.formats.time(plan.day, Double(start))). The old suggestion finds another gap, or use “Not today” to drop it.")
                }
            }
        }
        .navigationTitle("Swap it")
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
