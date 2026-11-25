import SwiftUI
import LittlesKit

/// Adds or edits one log entry. The fields shown depend on its kind.
struct LogSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var entry: LogEntry
    let isNew: Bool
    @State private var pickingFoods = false
    @State private var stillGoing = false

    init(entry: LogEntry, isNew: Bool) {
        _entry = State(initialValue: entry)
        self.isNew = isNew
        _stillGoing = State(initialValue: entry.kind.isTimed && entry.end == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let kid = model.kid(entry.kidID) {
                    Section {
                        HStack(spacing: 10) {
                            KidBadge(kid: kid, size: 30)
                            Text(kid.name).font(.headline)
                            Spacer()
                            Text(entry.kind.emoji).font(.title2)
                        }
                    }
                }
                fields
                Section("When") {
                    DatePicker(entry.kind.isTimed ? "Started" : "Time", selection: $entry.start)
                    if entry.kind.isTimed {
                        Toggle("Still going", isOn: $stillGoing)
                        if !stillGoing {
                            DatePicker("Ended", selection: endBinding, in: entry.start...)
                            Text("Lasted \(Dates.duration(endBinding.wrappedValue.timeIntervalSince(entry.start)))")
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                Section("Note") {
                    TextField("Anything to remember", text: $entry.note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) {
                            model.deleteLog(entry.id)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(entry.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        var saved = entry
                        if saved.kind.isTimed {
                            saved.end = stillGoing ? nil : endBinding.wrappedValue
                        }
                        model.save(saved)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(entry.kind == .solids && entry.bites.isEmpty && entry.note.isEmpty)
                }
            }
            .sheet(isPresented: $pickingFoods) {
                FoodPicker(kidID: entry.kidID, chosen: Set(entry.bites.map { $0.foodID })) { ids in
                    let kept = entry.bites.filter { ids.contains($0.foodID) }
                    let added = ids.filter { id in !kept.contains { $0.foodID == id } }.sorted().map { FoodBite(foodID: $0) }
                    entry.bites = kept + added
                }
                .environmentObject(model)
            }
        }
    }

    private var endBinding: Binding<Date> {
        Binding(get: { max(entry.end ?? Date(), entry.start) }, set: { entry.end = $0 })
    }

    @ViewBuilder
    private var fields: some View {
        switch entry.kind {
        case .bottle:
            amountSection
            Section("What's in it") {
                Picker("Milk", selection: Binding(get: { entry.milk ?? .formula }, set: { entry.milk = $0 })) {
                    ForEach(MilkType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
        case .pump:
            amountSection
            Section("Side") { sidePicker }
        case .nursing:
            Section("Side") { sidePicker }
            if isNew {
                Section {
                    Button {
                        model.start(.nursing, kidID: entry.kidID, side: entry.side ?? .left)
                        dismiss()
                    } label: {
                        Label("Start a timer instead", systemImage: "timer")
                    }
                }
            }
        case .diaper:
            Section("Diaper") {
                Picker("Diaper", selection: Binding(get: { entry.diaper ?? .wet }, set: { entry.diaper = $0 })) {
                    ForEach(DiaperKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .potty:
            Section("Potty") {
                Picker("Potty", selection: Binding(get: { entry.potty ?? .pee }, set: { entry.potty = $0 })) {
                    ForEach(PottyKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .solids:
            mealSection
        case .meds:
            Section("Medicine") {
                TextField("Name, like Infant Tylenol", text: $entry.medicine)
                TextField("Dose, like 2.5 mL", text: $entry.dose)
            }
            Section {
                Text("Check the dose with your pediatrician or the package, by weight.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        case .temperature:
            Section("Temperature") {
                Stepper(value: Binding(get: { entry.temperatureF ?? 98.6 }, set: { entry.temperatureF = $0 }),
                        in: 94...106, step: 0.1) {
                    Text(String(format: "%.1f°F", entry.temperatureF ?? 98.6))
                        .font(Theme.display(22))
                        .foregroundStyle((entry.temperatureF ?? 98.6) >= 100.4 ? Theme.warn : Theme.ink)
                }
                if (entry.temperatureF ?? 0) >= 100.4 {
                    Text("100.4°F or higher counts as a fever. Under 3 months, call the doctor for any fever.")
                        .font(.footnote)
                        .foregroundStyle(Theme.warn)
                }
            }
        case .growth:
            Section("Measurements") {
                numberField("Weight (lb)", value: $entry.weightLb)
                numberField("Height (in)", value: $entry.heightIn)
                numberField("Head (in)", value: $entry.headIn)
            }
        case .sleep, .bath, .note:
            EmptyView()
        }
    }

    private var amountSection: some View {
        Section("Amount") {
            Stepper(value: Binding(get: { entry.amountOz ?? 0 }, set: { entry.amountOz = $0 }), in: 0...16, step: 0.5) {
                Text(Measure.oz(entry.amountOz ?? 0))
                    .font(Theme.display(24))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([2.0, 3, 4, 5, 6, 7, 8], id: \.self) { ounces in
                        Button(Measure.oz(ounces)) { entry.amountOz = ounces }
                            .buttonStyle(.bordered)
                            .tint(entry.amountOz == ounces ? Theme.accent : Theme.muted)
                    }
                }
            }
        }
    }

    private var sidePicker: some View {
        Picker("Side", selection: Binding(get: { entry.side ?? .left }, set: { entry.side = $0 })) {
            ForEach(Side.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var mealSection: some View {
        Section {
            ForEach($entry.bites) { $bite in
                BiteRow(bite: $bite)
            }
            .onDelete { entry.bites.remove(atOffsets: $0) }
            Button {
                pickingFoods = true
            } label: {
                Label(entry.bites.isEmpty ? "Choose foods" : "Add or remove foods", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Foods")
        } footer: {
            Text("Mark a reaction for hives, rash, swelling, vomiting or coughing after eating. For trouble breathing or swelling of the face, call 911.")
        }
    }

    private func numberField(_ title: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }
}

/// One food in a meal: how it went, and a reaction switch.
struct BiteRow: View {
    @Binding var bite: FoodBite

    var body: some View {
        let food = FoodGuide.food(bite.foodID)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text((food?.emoji ?? "🍽️") + " " + (food?.name ?? bite.foodID))
                    .font(.headline)
                if let allergen = food?.allergen {
                    Pill(text: allergen.title, color: Theme.warn)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(Liking.allCases) { liking in
                    Button {
                        bite.liking = liking
                    } label: {
                        Text(liking.emoji)
                            .font(.title3)
                            .frame(width: 40, height: 34)
                            .background(bite.liking == liking ? Theme.accentSoft : Theme.sunk, in: Capsule())
                            .overlay(Capsule().stroke(bite.liking == liking ? Theme.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(liking.title)
                }
                Spacer()
                Toggle(isOn: $bite.reaction) {
                    Text("Reaction").font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
                .tint(Theme.warn)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Pick foods from the guide for a meal. Today's suggestions are on top.
struct FoodPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kidID: String
    @State var chosen: Set<String>
    let onDone: (Set<String>) -> Void
    @State private var search = ""

    init(kidID: String, chosen: Set<String>, onDone: @escaping (Set<String>) -> Void) {
        self.kidID = kidID
        _chosen = State(initialValue: chosen)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty, let kid = model.kid(kidID) {
                    let ideas = FoodProgress.suggestions(for: kid, logs: model.state.logs, now: Date())
                    if !ideas.isEmpty {
                        Section("Ideas for today") {
                            ForEach(ideas) { idea in row(idea.food, subtitle: idea.reason.title) }
                        }
                    }
                }
                ForEach(FoodCategory.allCases) { category in
                    let foods = FoodGuide.all.filter { $0.category == category && matches($0) }
                    if !foods.isEmpty {
                        Section(category.title) {
                            ForEach(foods) { food in row(food, subtitle: nil) }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search foods")
            .navigationTitle("Foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(chosen.count))") {
                        onDone(chosen)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func matches(_ food: FoodItem) -> Bool {
        search.isEmpty || food.name.localizedCaseInsensitiveContains(search)
    }

    private func row(_ food: FoodItem, subtitle: String?) -> some View {
        let tries = FoodProgress.stats(model.state.logs, kidID: kidID)[food.id]?.tries ?? 0
        return Button {
            if chosen.contains(food.id) { chosen.remove(food.id) } else { chosen.insert(food.id) }
        } label: {
            HStack(spacing: 12) {
                Text(food.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).foregroundStyle(Theme.ink)
                    Text(subtitle ?? (tries == 0 ? "New" : "Had \(tries)×"))
                        .font(.caption)
                        .foregroundStyle(tries == 0 ? Theme.accent : Theme.muted)
                }
                Spacer()
                if let allergen = food.allergen {
                    Text(allergen.emoji).accessibilityLabel(allergen.title)
                }
                Image(systemName: chosen.contains(food.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen.contains(food.id) ? Theme.accent : Theme.line)
            }
        }
    }
}
