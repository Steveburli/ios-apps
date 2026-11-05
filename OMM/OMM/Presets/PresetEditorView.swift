import SwiftUI
import OMMKit

/// Makes or changes a preset: a name, then each exercise or machine with the
/// muscle group it counts toward. Typing a common name fills in a guess.
struct PresetEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Preset
    @State private var confirmingDelete = false
    /// Rows whose group came from a guess, so further typing can update it.
    @State private var guessedRows: Set<UUID> = []
    @FocusState private var focusedRow: UUID?
    private let isNew: Bool

    init(sheet: AppModel.PresetSheet) {
        switch sheet {
        case .new:
            _draft = State(initialValue: Preset(exercises: [Preset.Exercise()]))
            isNew = true
        case .edit(let preset):
            _draft = State(initialValue: preset)
            isNew = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Gym Circuit", text: $draft.name)
                        .font(.body.weight(.semibold))
                } footer: {
                    Text("One tap of Log adds one set to the muscle group of every exercise below.")
                }

                Section {
                    ForEach($draft.exercises) { $exercise in
                        exerciseRow($exercise)
                    }
                    .onDelete { draft.exercises.remove(atOffsets: $0) }
                    Button {
                        let row = Preset.Exercise()
                        draft.exercises.append(row)
                        focusedRow = row.id
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Swipe left on one to remove it.")
                }

                if !draft.setsByGroup.isEmpty {
                    Section("One tap logs") {
                        ForEach(draft.setsByGroup, id: \.group.key) { entry in
                            HStack {
                                Circle()
                                    .fill(entry.group.category.color)
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                Text("\(entry.group.area) · \(entry.group.name)")
                                Spacer()
                                Text(entry.sets.counted("set"))
                                    .foregroundStyle(Theme.muted)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Preset", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                        model.savePreset(draft)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(!draft.isReady)
                }
            }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Preset", role: .destructive) {
                    model.deletePreset(draft)
                    dismiss()
                }
            } message: {
                Text("Sets you already logged with it stay logged.")
            }
        }
    }

    private func exerciseRow(_ exercise: Binding<Preset.Exercise>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Exercise or machine", text: exercise.name)
                .focused($focusedRow, equals: exercise.wrappedValue.id)
                .submitLabel(.done)
                .onChange(of: exercise.wrappedValue.name) { _, name in
                    // Keep guessing as the name is typed ("Lat" then "Lateral Raise"),
                    // but never replace a group picked from the menu.
                    let id = exercise.wrappedValue.id
                    guard exercise.wrappedValue.groupKey == nil || guessedRows.contains(id) else { return }
                    exercise.wrappedValue.groupKey = GroupGuess.group(for: name)?.key
                    if exercise.wrappedValue.groupKey == nil {
                        guessedRows.remove(id)
                    } else {
                        guessedRows.insert(id)
                    }
                }
            GroupMenu(groupKey: exercise.groupKey) {
                guessedRows.remove(exercise.wrappedValue.id)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Picks one of the 28 groups, by section and body area.
private struct GroupMenu: View {
    @Binding var groupKey: String?
    var onPick: () -> Void

    var body: some View {
        Menu {
            ForEach(Catalog.sections) { section in
                Section(section.category.title) {
                    ForEach(section.rows) { row in
                        Menu(row.area) {
                            ForEach(row.groups) { group in
                                Button(group.name) {
                                    groupKey = group.key
                                    onPick()
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let group = groupKey.flatMap(Catalog.group) {
                    Circle()
                        .fill(group.category.color)
                        .frame(width: 8, height: 8)
                    Text("\(group.area) · \(group.name)")
                        .foregroundStyle(group.category.color)
                } else {
                    Text("Pick a muscle group")
                        .foregroundStyle(Theme.core)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            .font(.footnote.weight(.semibold))
        }
        .accessibilityLabel("Muscle group")
        .accessibilityValue(groupKey.flatMap(Catalog.group).map { "\($0.area), \($0.name)" } ?? "Not picked")
    }
}
