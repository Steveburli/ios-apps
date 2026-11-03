import SwiftUI
import DoThisNowKit

/// The Replan preview: what moves to later today, and a choice for each
/// thing that doesn't fit. Nothing changes until you tap Replan.
struct ReplanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var leftovers: [String: Leftover] = [:]

    var body: some View {
        let replan = model.engine.replan()
        let day = model.today
        let f = model.formats
        NavigationStack {
            Group {
                if replan.isEmpty {
                    ContentUnavailableView("All caught up", systemImage: "checkmark.circle",
                                           description: Text("Nothing from earlier today is waiting."))
                } else {
                    List {
                        if !replan.moves.isEmpty {
                            Section {
                                ForEach(replan.moves, id: \.id) { move in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(move.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Theme.ink)
                                            Text("Was \(f.time(day, Double(move.from)))")
                                                .font(.caption)
                                                .foregroundStyle(Theme.ink3)
                                                .strikethrough()
                                        }
                                        Spacer()
                                        Text(f.time(day, Double(move.to)))
                                            .font(.subheadline.weight(.bold).monospacedDigit())
                                            .foregroundStyle(Theme.block)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            } header: {
                                Text("Moves to later today")
                            } footer: {
                                Text("Each one goes in the first open gap. Events, work and the blocks you've already done stay put.")
                            }
                        }
                        if !replan.overflow.isEmpty {
                            Section {
                                ForEach(replan.overflow, id: \.id) { item in
                                    overflowRow(item)
                                }
                            } header: {
                                Text("No room left today")
                            } footer: {
                                Text("Pick what happens to each one.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Catch up on today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replan") { model.applyReplan(replan, leftovers: leftovers) }
                        .fontWeight(.bold)
                        .disabled(replan.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func overflowRow(_ item: Replan.Overflow) -> some View {
        let tomorrowFull = item.tomorrow == nil
        let fallback: Leftover = tomorrowFull ? .inbox : .tomorrow
        let choice = Binding<Leftover>(
            get: { leftovers[item.id] ?? fallback },
            set: { leftovers[item.id] = $0 }
        )
        let tomorrow = model.today.adding(days: 1, calendar: model.calendar)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(TimeText.duration(item.minutes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink3)
            }
            Picker("What happens to it", selection: choice) {
                ForEach(Leftover.allCases.filter { !(tomorrowFull && $0 == .tomorrow) }, id: \.self) { option in
                    Text(option == .tomorrow ? "Tomorrow" : option == .inbox ? "Inbox" : option.label)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            if let start = item.tomorrow, choice.wrappedValue == .tomorrow {
                Text("Tomorrow at \(model.formats.time(tomorrow, Double(start))), in the first gap that fits.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            } else if tomorrowFull {
                Text("Tomorrow is full too.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.vertical, 4)
    }
}
