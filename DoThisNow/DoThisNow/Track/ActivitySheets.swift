import SwiftUI
import DoThisNowKit

/// An activity's history: the usual time, the spread, and every run.
struct ActivitySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let activityID: String
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let activity = model.state.activity(activityID) {
                    content(activity)
                } else {
                    ContentUnavailableView("Deleted", systemImage: "trash")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    NavigationLink("Edit") {
                        ActivityFormView(activity: model.state.activity(activityID), embedded: true)
                    }
                }
            }
        }
    }

    private func content(_ activity: Activity) -> some View {
        let timings = model.state.timings(for: activity.name, activityID: activity.id)
        let estimate = model.state.estimate(title: activity.name, activityID: activity.id)
        let recent = timings.prefix(Estimator.window).map(\.minutes)
        return List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: activity.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text(activity.name)
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.ink)
                }
                if timings.isEmpty {
                    Text("Not timed yet. Tap it on the Track tab when you start, and again when you’re done.")
                        .foregroundStyle(Theme.ink2)
                } else {
                    LabeledContent("Usually", value: TimeText.duration(estimate.minutes))
                    Text(estimate.detail.prefix(1).uppercased() + estimate.detail.dropFirst())
                        .font(.footnote)
                        .foregroundStyle(Theme.ink3)
                    if let low = recent.min(), let high = recent.max(), recent.count > 1 {
                        LabeledContent("Fastest", value: TimeText.clock(low * 60))
                        LabeledContent("Slowest", value: TimeText.clock(high * 60))
                    }
                }
                if !activity.aliases.isEmpty {
                    LabeledContent("Also counts", value: activity.aliases.joined(separator: ", "))
                }
            }

            Section {
                Button("Add a time you forgot") { model.sheet = .newTiming(activity.id) }
                ForEach(timings.prefix(60)) { timing in
                    TimingRow(timing: timing, showsDate: true)
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            } header: {
                Text("History")
            } footer: {
                Text("Estimates use your last \(Estimator.window) times. Runs far shorter or longer than usual are left out, so one rushed or interrupted morning doesn’t throw them off.")
            }

            Section {
                Button("Delete \(activity.name)", role: .destructive) { confirmingDelete = true }
            }
        }
        .confirmationDialog("Delete \(activity.name) and all its times?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteActivity(activity.id) }
        }
    }
}

/// Name, icon, and other names for an activity.
struct ActivityFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let activity: Activity?
    var embedded = false
    @State private var draft = Activity(name: "")
    @State private var aliases = ""
    @State private var loaded = false

    private static let symbols = [
        "timer", "shower", "tshirt", "fork.knife", "cup.and.saucer", "car", "bus", "figure.walk", "figure.run",
        "dumbbell", "bed.double", "book", "laptopcomputer", "envelope", "phone", "cart", "washer", "sink",
        "leaf", "pawprint", "house", "paintbrush", "wrench.and.screwdriver", "music.note",
    ]

    var body: some View {
        if embedded {
            form
        } else {
            NavigationStack { form }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("What do you do? e.g. Shower", text: $draft.name)
                    .font(.headline)
            }
            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            draft.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .foregroundStyle(draft.symbol == symbol ? Theme.accentInk : Theme.ink)
                                .background(draft.symbol == symbol ? Theme.accent : Theme.surface2,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                        .accessibilityAddTraits(draft.symbol == symbol ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                TextField("e.g. Take a shower, Morning shower", text: $aliases, axis: .vertical)
            } header: {
                Text("Also called")
            } footer: {
                Text("Other names it goes by in Reminders, Google Tasks or your task list, separated by commas. Their estimates use these times too.")
            }
        }
        .tint(Theme.accent)
        .navigationTitle(activity == nil ? "New activity" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    draft.aliases = aliases.split(separator: ",").map(String.init)
                    model.save(draft)
                }
                .fontWeight(.bold)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let activity {
                draft = activity
                aliases = activity.aliases.joined(separator: ", ")
            }
        }
    }
}

/// One timed run: when it started and how long it took.
struct TimingFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let timing: Timing?
    let activityID: String?
    @State private var start = Date()
    @State private var minutes = 15
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title)
                        .font(.headline)
                    DatePicker("Started", selection: $start, in: ...Date())
                    MinuteStepper(title: "Took", minutes: $minutes, range: 1...600, step: 1)
                }
                if let timing {
                    Section {
                        Button("Delete this time", role: .destructive) { model.deleteTiming(timing.id) }
                    }
                }
            }
            .tint(Theme.accent)
            .navigationTitle(timing == nil ? "Add a time" : "Edit time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.bold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let timing {
                    start = timing.start
                    minutes = max(1, Int(timing.minutes.rounded()))
                } else {
                    minutes = model.state.estimate(title: title, activityID: activityID).minutes
                    start = Date().addingTimeInterval(-Double(minutes) * 60)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        timing?.title ?? model.state.activity(activityID)?.name ?? "Timing"
    }

    private func save() {
        var edited = timing ?? Timing(activityID: activityID, title: title, start: start, seconds: 0)
        edited.start = start
        // Keep the seconds when the minutes weren't changed.
        if let timing, Int(timing.minutes.rounded()) == minutes {
            edited.seconds = timing.seconds
        } else {
            edited.seconds = Double(minutes) * 60
        }
        model.save(edited)
    }
}
