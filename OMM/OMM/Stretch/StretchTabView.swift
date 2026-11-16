import SwiftUI
import OMMKit

/// The Stretch tab: a routine made for today from what you trained, your own
/// saved routines, and a quick pick by body area.
struct StretchTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 14) {
                header
                TodayStretchCard()
                MyRoutinesCard()
                ByAreaCard()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $model.routineSheet) { sheet in
            StretchRoutineEditor(sheet: sheet)
                .environment(model)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Stretch")
                .font(.system(size: 44, weight: .heavy))
                .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
            Text("Stretches and yoga, with a timer for every hold")
                .font(.subheadline.weight(.medium))
                .opacity(0.92)
        }
        .foregroundStyle(Color.white)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// "For you today": built from the groups trained today and yesterday.
private struct TodayStretchCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.todayStretch()
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("For You Today")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("about \(Stretches.minutes(for: today.steps)) min")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
                Text(reason(today))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: upcomingBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add what's coming up next")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.text)
                        Text(upcomingDetail)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.primary)
                .disabled(today.sore.isEmpty)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Length")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Picker("Length", selection: minutesBinding) {
                        ForEach(StretchPlanner.lengthChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                MovesStrip(steps: today.steps)

                Button("Start (\(today.steps.count.counted("hold")))") {
                    model.startStretch(steps: today.steps, title: nil)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(today.steps.isEmpty)
                Button {
                    model.routineSheet = .new(routine(from: today.steps))
                } label: {
                    Label("Save as My Routine", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                }
                .disabled(today.steps.isEmpty)
            }
        }
    }

    private func reason(_ today: AppModel.TodayStretch) -> String {
        if today.sore.isEmpty {
            if today.upcoming.isEmpty { return "Nothing trained lately, so this is a little of everything." }
            return "Nothing trained today or yesterday, so this loosens up what's next: \(names(today.upcoming))."
        }
        return "For what you worked today and yesterday: \(names(today.sore))."
    }

    private var upcomingDetail: String {
        let upcoming = model.upcomingStretchGroups()
        return upcoming.isEmpty ? "Nothing left in the program" : names(upcoming)
    }

    private func names(_ groups: [MuscleGroup]) -> String {
        groups.map { "\($0.area) \($0.name)" }.joined(separator: ", ")
    }

    /// The automatic routine as a routine to name and keep.
    private func routine(from steps: [StretchStep]) -> StretchRoutine {
        var items: [StretchRoutine.Item] = []
        for step in steps where !items.contains(where: { $0.stretchID == step.stretch.id }) {
            items.append(.init(stretchID: step.stretch.id, holdSeconds: step.holdSeconds))
        }
        return StretchRoutine(items: items)
    }

    private var upcomingBinding: Binding<Bool> {
        Binding(get: { model.stretchUpcoming }, set: { model.stretchUpcoming = $0 })
    }

    private var minutesBinding: Binding<Int> {
        Binding(get: { model.stretchMinutes }, set: { model.stretchMinutes = $0 })
    }
}

/// A sideways row of the moves in a routine, each with its picture.
private struct MovesStrip: View {
    let steps: [StretchStep]

    var body: some View {
        let moves = uniqueMoves
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(moves, id: \.id) { stretch in
                    VStack(spacing: 4) {
                        StretchFigureView(stretchID: stretch.id)
                            .frame(width: 56, height: 56)
                        Text(stretch.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(width: 72)
                    }
                    .padding(6)
                    .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Moves: " + moves.map(\.name).joined(separator: ", "))
    }

    private var uniqueMoves: [Stretch] {
        var seen = Set<String>()
        return steps.map(\.stretch).filter { seen.insert($0.id).inserted }
    }
}

/// Saved routines, each started with one tap.
private struct MyRoutinesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("My Routines")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        model.routineSheet = .new(StretchRoutine())
                    } label: {
                        Label("New Routine", systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                if model.stretchRoutines.isEmpty {
                    Text("Build your own: pick stretches and yoga poses, set how long to hold each one, and save it by name. Then one tap starts it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(model.stretchRoutines) { routine in
                        row(routine)
                    }
                }
            }
        }
    }

    private func row(_ routine: StretchRoutine) -> some View {
        HStack(spacing: 12) {
            Button {
                model.routineSheet = .edit(routine)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    Text("\(routine.items.count.counted("move")) · about \(Stretches.minutes(for: routine.steps)) min · Edit")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the routine to change it")
            Button {
                model.startRoutine(routine)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(routine.steps.isEmpty)
            .opacity(routine.steps.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Start \(routine.name)")
        }
        .padding(12)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The old "Just Stretch": pick body areas, two stretches each, 30-second holds.
private struct ByAreaCard: View {
    @Environment(AppModel.self) private var model
    @State private var chosen: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("By Body Area")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Two stretches per area, \(Stretches.holdSeconds)-second holds, both sides where it applies.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Catalog.areas, id: \.self) { area in
                        chip(area)
                    }
                }
                Button(startTitle) {
                    model.startStretch(areas: Catalog.areas.filter(chosen.contains))
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(chosen.isEmpty)
            }
        }
    }

    private var startTitle: String {
        guard !chosen.isEmpty else { return "Pick Areas to Start" }
        let minutes = Stretches.minutes(for: Stretches.routine(areas: Array(chosen)))
        return "Start (about \(minutes) min)"
    }

    private func chip(_ area: String) -> some View {
        let on = chosen.contains(area)
        return Button {
            if on { chosen.remove(area) } else { chosen.insert(area) }
        } label: {
            Text(area)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(on ? Color.white : Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(on ? Theme.primary : Theme.sheet, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
