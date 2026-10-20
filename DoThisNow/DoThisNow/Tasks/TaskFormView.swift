import SwiftUI
import DoThisNowKit

struct TaskFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let original: TaskItem?
    @State private var draft: TaskItem
    @State private var places: Set<Place>
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var error: String?
    @State private var confirmingDelete = false
    @FocusState private var titleFocused: Bool

    init(task: TaskItem?) {
        original = task
        let start = task ?? TaskItem(title: "", created: Date())
        _draft = State(initialValue: start)
        _places = State(initialValue: Set(start.places.isEmpty ? [.anywhere] : start.places))
        _hasDeadline = State(initialValue: start.deadline != nil)
        _deadline = State(initialValue: start.deadline?.startDate(calendar: .autoupdatingCurrent) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What is it?") {
                    TextField("e.g. Clean out the garage", text: $draft.title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                }

                Section("What kind?") {
                    ChoiceChips(options: [(TaskKind.task, "One-time task"), (.recurring, "Recurring goal"), (.errand, "Errand")],
                                selection: $draft.kind)
                }

                Section {
                    if draft.kind == .recurring {
                        MinuteStepper(title: "How much time a week?", minutes: $draft.weekly, range: 5...3000)
                        MinuteStepper(title: "Smallest block it can be broken into", minutes: $draft.minBlock, range: 5...240)
                    } else {
                        MinuteStepper(title: "How long will it take, start to finish?", minutes: $draft.estimate)
                    }
                }

                if draft.kind == .errand {
                    Section("Where do you need to go?") {
                        TextField("Store name or address", text: $draft.place)
                    }
                } else {
                    Section {
                        FlowLayout {
                            ForEach(Place.taskPlaces, id: \.self) { place in
                                Chip(title: place.label, isOn: places.contains(place)) { toggle(place) }
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Where can you do it?")
                    } footer: {
                        Text("Pick all that apply.")
                    }
                }

                Section {
                    Toggle("Deadline", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Due", selection: $deadline, displayedComponents: .date)
                    }
                    Picker("Priority level", selection: $draft.tier) {
                        ForEach(Tier.all, id: \.self) { tier in
                            Text(Tier.name(tier)).tag(tier)
                        }
                    }
                }

                if hasDeadline {
                    Section("How mad will you be if it isn’t done by then?") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stakesLabel(draft.stakes))
                                .font(.headline)
                                .foregroundStyle(Theme.accent)
                            Slider(value: stakes, in: 0...10, step: 1) {
                                Text("How mad")
                            } minimumValueLabel: {
                                Text("Shrug").font(.caption)
                            } maximumValueLabel: {
                                Text("Furious").font(.caption)
                            }
                            .tint(Theme.accent)
                            .accessibilityValue(stakesLabel(draft.stakes))
                        }
                    }
                }

                if draft.kind != .errand {
                    Section("Can this be binged?") {
                        ChoiceChips(options: [(true, "Yes, I can go for hours"), (false, "No, in doses")], selection: $draft.binge)
                        if !draft.binge {
                            MinuteStepper(title: "Most time you can spend on it at once without losing your mind",
                                          minutes: $draft.maxSession, range: 5...480)
                        }
                    }
                }

                Section("Does it need focus?") {
                    ChoiceChips(options: [(FocusLevel.deep, "Needs focus"), (.light, "Fine while multitasking")], selection: $draft.focus)
                }

                Section("Sitting or moving?") {
                    ChoiceChips(options: [(Posture.sit, "Sitting"), (.move, "Moving around"), (.any, "Either")], selection: $draft.posture)
                }

                Section {
                    Toggle("It gets me outside", isOn: $draft.outside)
                    Toggle("I can do it in the same room as the TV", isOn: $draft.tv)
                }

                Section("Notes") {
                    TextField("Optional", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.bad)
                    }
                }

                if original != nil {
                    Section {
                        Button("Delete task", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .tint(Theme.accent)
            .navigationTitle(original == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(original == nil ? "Add task" : "Save") { save() }
                        .fontWeight(.bold)
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { model.deleteTask(draft.id) }
            } message: {
                Text("Its logged time goes too.")
            }
            .onAppear {
                if original == nil { titleFocused = true }
            }
        }
    }

    private var stakes: Binding<Double> {
        Binding(get: { Double(draft.stakes) }, set: { draft.stakes = Int($0.rounded()) })
    }

    private func toggle(_ place: Place) {
        if place == .anywhere {
            places = [.anywhere]
            return
        }
        places.remove(.anywhere)
        if places.contains(place) { places.remove(place) } else { places.insert(place) }
        if places.isEmpty { places = [.anywhere] }
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            error = "Give the task a name first."
            titleFocused = true
            return
        }
        var task = draft
        task.title = title
        var chosen: [Place] = task.kind == .errand ? [.errand] : Place.taskPlaces.filter { places.contains($0) }
        if chosen.isEmpty || chosen.contains(.anywhere) { chosen = [.anywhere] }
        task.places = chosen
        task.place = task.place.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.deadline = hasDeadline ? CalendarDay(deadline, calendar: model.calendar) : nil
        task.isExample = false
        model.save(task)
    }
}
