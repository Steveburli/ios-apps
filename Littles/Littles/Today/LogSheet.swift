import SwiftUI
import PhotosUI
import LittlesKit

/// Adds or edits one log entry. The fields shown depend on its kind.
struct LogSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var entry: LogEntry
    let isNew: Bool
    @State private var pickingFoods = false
    @State private var stillGoing = false
    @State private var photoItem: PhotosPickerItem?

    init(entry: LogEntry, isNew: Bool) {
        _entry = State(initialValue: entry)
        self.isNew = isNew
        _stillGoing = State(initialValue: entry.kind.isTimed && entry.end == nil)
    }

    private var units: Units { model.units }

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
                Section(noteTitle) {
                    TextField(notePrompt, text: $entry.note, axis: .vertical)
                        .lineLimit(1...4)
                }
                photoSection
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
                    .disabled(!canSave)
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
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let name = model.savePhoto(data) {
                        if !entry.photo.isEmpty && isNew { model.deletePhoto(entry.photo) }
                        entry.photo = name
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        switch entry.kind {
        case .solids: return !entry.bites.isEmpty || !entry.note.isEmpty
        case .first, .quote: return !entry.note.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private var noteTitle: String {
        switch entry.kind {
        case .first: return "What happened"
        case .quote: return "What they said"
        case .tooth: return "Which tooth"
        default: return "Note"
        }
    }

    private var notePrompt: String {
        switch entry.kind {
        case .first: return "First steps, first word, first haircut…"
        case .quote: return "Word for word"
        case .tooth: return "Like bottom front left"
        default: return "Anything to remember"
        }
    }

    private var endBinding: Binding<Date> {
        Binding(get: { max(entry.end ?? Date(), entry.start) }, set: { entry.end = $0 })
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            if let image = model.photo(entry.photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("Remove photo", role: .destructive) { entry.photo = "" }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(entry.photo.isEmpty ? "Add a photo" : "Change photo", systemImage: "photo.on.rectangle.angled")
            }
        }
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
            Section {
                TextField("Name, like Infant Tylenol", text: $entry.medicine)
                TextField("Dose, like 2.5 mL", text: $entry.dose)
            } header: {
                Text("Medicine")
            } footer: {
                Text(medicineFooter)
            }
        case .temperature:
            temperatureSection
        case .symptom:
            symptomSection
            temperatureSection
        case .growth:
            Section("Measurements") {
                numberField("Weight (\(units.weightUnit))", value: converted(\.weightLb, show: units.showWeight, save: units.saveWeight))
                numberField("Height (\(units.lengthUnit))", value: converted(\.heightIn, show: units.showLength, save: units.saveLength))
                numberField("Head (\(units.lengthUnit))", value: converted(\.headIn, show: units.showLength, save: units.saveLength))
            }
        case .screen, .outside:
            Section(entry.kind == .screen ? "Screen time" : "Time outside") {
                Stepper(value: Binding(get: { entry.minutes ?? 30 }, set: { entry.minutes = $0 }), in: 5...600, step: 5) {
                    Text(Dates.duration(Double(entry.minutes ?? 30) * 60)).font(Theme.display(22))
                }
            }
        case .sleep, .bath, .note, .tooth, .brush, .first, .quote:
            EmptyView()
        }
    }

    private var medicineFooter: String {
        if let rule = MedicineTimer.rule(for: entry.medicine) {
            return rule.note + " Give the dose for their weight from the package chart or your pediatrician."
        }
        return "Give the dose for their weight from the package chart or your pediatrician."
    }

    /// A binding that shows a saved US value in the chosen units.
    private func converted(_ path: WritableKeyPath<LogEntry, Double?>, show: @escaping (Double) -> Double,
                           save: @escaping (Double) -> Double) -> Binding<Double?> {
        Binding(
            get: { entry[keyPath: path].map { (show($0) * 100).rounded() / 100 } },
            set: { entry[keyPath: path] = $0.map(save) }
        )
    }

    private var amountSection: some View {
        let shown = units.showVolume(entry.amountOz ?? 0)
        let step = units.isMetric ? 10.0 : 0.5
        let presets: [Double] = units.isMetric ? [60, 90, 120, 150, 180, 210, 240] : [2, 3, 4, 5, 6, 7, 8]
        return Section("Amount") {
            Stepper(value: Binding(get: { shown }, set: { entry.amountOz = units.saveVolume(max(0, $0)) }),
                    in: 0...(units.isMetric ? 480 : 16), step: step) {
                Text(units.volume(entry.amountOz ?? 0))
                    .font(Theme.display(24))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { value in
                        Button(units.isMetric ? "\(Int(value)) ml" : Measure.oz(value)) { entry.amountOz = units.saveVolume(value) }
                            .buttonStyle(.bordered)
                            .tint(abs(shown - value) < 0.01 ? Theme.accent : Theme.muted)
                    }
                }
            }
        }
    }

    private var temperatureSection: some View {
        let fahrenheit = entry.temperatureF ?? 98.6
        return Section("Temperature") {
            Stepper(value: Binding(get: { units.showTemperature(fahrenheit) },
                                   set: { entry.temperatureF = units.saveTemperature($0) }),
                    in: units.isMetric ? 34...42 : 94...107, step: units.isMetric ? 0.1 : 0.1) {
                Text(units.temperature(fahrenheit))
                    .font(Theme.display(22))
                    .foregroundStyle(fahrenheit >= 100.4 ? Theme.warn : Theme.ink)
            }
            if entry.kind == .symptom && entry.temperatureF == nil {
                Text("Tap + or − to add a temperature.").font(.footnote).foregroundStyle(Theme.muted)
            }
            if fahrenheit >= 100.4 {
                Text("100.4°F (38°C) or higher counts as a fever. Under 3 months, call the doctor for any fever.")
                    .font(.footnote)
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    private var symptomSection: some View {
        Section("Symptoms") {
            FlowChips(items: SickAdvice.symptoms, selected: Set(entry.symptoms)) { symptom in
                if entry.symptoms.contains(symptom) {
                    entry.symptoms.removeAll { $0 == symptom }
                } else {
                    entry.symptoms.append(symptom)
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

/// Tappable chips that wrap onto as many lines as they need.
struct FlowChips: View {
    let items: [String]
    let selected: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Theme.ink)
                        .background(on ? Theme.accent : Theme.sunk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Lays children out left to right, wrapping to new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
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
