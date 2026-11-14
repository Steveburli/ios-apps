import SwiftUI
import OMMKit

/// Builds or changes a saved stretch routine: a name, the moves in order and
/// how long to hold each one. Moves are added from the library below, by body
/// area and by stretch or yoga.
struct StretchRoutineEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StretchRoutine
    @State private var confirmingDelete = false
    @State private var areaFilter: String?
    @State private var kindFilter: Stretch.Kind?
    private let isNew: Bool

    init(sheet: AppModel.RoutineSheet) {
        switch sheet {
        case .new(let routine):
            _draft = State(initialValue: routine)
            isNew = true
        case .edit(let routine):
            _draft = State(initialValue: routine)
            isNew = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Morning Loosen-Up", text: $draft.name)
                        .font(.body.weight(.semibold))
                }

                Section {
                    if draft.items.isEmpty {
                        Text("Add moves from the list below.")
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach($draft.items) { $item in
                        itemRow($item)
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                    .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    HStack {
                        Text("Moves")
                        Spacer()
                        if draft.items.count > 1 {
                            EditButton()
                                .font(.footnote.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                } footer: {
                    Text(totalText)
                }

                Section {
                    filters
                    ForEach(filteredLibrary) { stretch in
                        libraryRow(stretch)
                    }
                } header: {
                    Text("Add Moves")
                }

                if !isNew {
                    Section {
                        Button("Delete Routine", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                        model.saveRoutine(draft)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(!draft.isReady)
                }
            }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Routine", role: .destructive) {
                    model.deleteRoutine(draft)
                    dismiss()
                }
            }
        }
    }

    private var totalText: String {
        let steps = draft.steps
        guard !steps.isEmpty else { return "Hold times are per side for moves done on both sides." }
        let seconds = Stretches.seconds(for: steps)
        return "\(steps.count.counted("hold")), about \(Stretches.minutes(for: steps)) min of holding (\(Clock.string(seconds))). Hold times are per side for moves done on both sides. Swipe left to remove a move."
    }

    private func itemRow(_ item: Binding<StretchRoutine.Item>) -> some View {
        let stretch = item.wrappedValue.stretch
        return HStack(spacing: 10) {
            StretchFigureView(stretchID: item.wrappedValue.stretchID)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(stretch?.name ?? "Removed move")
                    .font(.body.weight(.semibold))
                if stretch?.eachSide == true {
                    Text("Each side")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 6)
            Picker("Hold", selection: item.holdSeconds) {
                ForEach(holdChoices(including: item.wrappedValue.holdSeconds), id: \.self) { seconds in
                    Text("\(seconds) sec").tag(seconds)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("Hold for \(stretch?.name ?? "move")")
        }
    }

    /// The usual choices, plus an odd saved value so it still shows.
    private func holdChoices(including current: Int) -> [Int] {
        Stretches.holdChoices.contains(current) ? Stretches.holdChoices : (Stretches.holdChoices + [current]).sorted()
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Kind", selection: $kindFilter) {
                Text("All").tag(Stretch.Kind?.none)
                ForEach(Stretch.Kind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(Stretch.Kind?.some(kind))
                }
            }
            .pickerStyle(.segmented)
            Picker("Body area", selection: $areaFilter) {
                Text("Every area").tag(String?.none)
                ForEach(Catalog.areas, id: \.self) { area in
                    Text(area).tag(String?.some(area))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
    }

    private var filteredLibrary: [Stretch] {
        Stretches.library.filter { stretch in
            (areaFilter == nil || stretch.area == areaFilter) && (kindFilter == nil || stretch.kind == kindFilter)
        }
    }

    private func libraryRow(_ stretch: Stretch) -> some View {
        let count = draft.items.filter { $0.stretchID == stretch.id }.count
        return Button {
            draft.items.append(.init(stretchID: stretch.id, holdSeconds: stretch.holdSeconds))
        } label: {
            HStack(spacing: 10) {
                StretchFigureView(stretchID: stretch.id)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stretch.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("\(stretch.kind.title) · \(stretch.area)\(stretch.eachSide ? " · each side" : "")")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 6)
                Image(systemName: count > 0 ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(count > 0 ? Theme.success : Theme.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(stretch.name)")
        .accessibilityValue(count > 0 ? "Added" : "")
    }
}
