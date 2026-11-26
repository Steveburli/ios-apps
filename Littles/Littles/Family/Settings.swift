import SwiftUI
import LittlesKit

/// Units, night mode, reminders and potty training, as List sections.
struct SettingsSections: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            Picker("Units", selection: binding(\.metric)) {
                Text("oz, lb, in, °F").tag(false)
                Text("ml, kg, cm, °C").tag(true)
            }
            Picker("Night mode", selection: binding(\.nightMode)) {
                ForEach(NightMode.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Night mode dims the app and turns it red for middle-of-the-night feeds.")
        }
        Section {
            Toggle("Leave-for-school countdown", isOn: binding(\.countdown))
            Stepper("Drive to school: \(model.state.settings.travelMinutes) min", value: binding(\.travelMinutes), in: 0...90, step: 5)
            Toggle("Next fever-medicine dose", isOn: binding(\.medicineReminders))
            Toggle("Checkups a week ahead", isOn: binding(\.checkupReminders))
        } header: {
            Text("Reminders")
        } footer: {
            Text("The countdown shows on Today before the first drop-off, and a reminder comes 15 minutes before it's time to leave, with the pack list.")
        }
        Section {
            ForEach(model.state.kids.filter { $0.ageMonths(on: Date()) >= 15 }) { kid in
                PottyPlanRow(kid: kid)
            }
        } header: {
            Text("Potty training")
        } footer: {
            Text("Reminders to try the potty during the day, a sticker tally and a dry-day streak on Today.")
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<FamilySettings, Value>) -> Binding<Value> {
        Binding(get: { model.state.settings[keyPath: path] }, set: { model.state.settings[keyPath: path] = $0 })
    }
}

struct PottyPlanRow: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid

    var body: some View {
        let plan = model.state.settings.potty[kid.id] ?? PottyPlan()
        Toggle("\(kid.name)", isOn: Binding(get: { plan.on }, set: { on in update { $0.on = on } }))
        if plan.on {
            Stepper("Every \(plan.every) min", value: Binding(get: { plan.every }, set: { value in update { $0.every = value } }), in: 15...180, step: 15)
            MinutesPicker(title: "From", minutes: Binding(get: { plan.from }, set: { value in update { $0.from = value } }))
            MinutesPicker(title: "Until", minutes: Binding(get: { plan.to }, set: { value in update { $0.to = value } }))
        }
    }

    private func update(_ change: (inout PottyPlan) -> Void) {
        var plan = model.state.settings.potty[kid.id] ?? PottyPlan()
        change(&plan)
        model.state.settings.potty[kid.id] = plan
        if plan.on { Notifier.requestPermission() }
    }
}

/// Edit a picture chart's title, kids and steps.
struct ChartEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var chart: RoutineChart
    let isNew: Bool

    init(chart: RoutineChart, isNew: Bool) {
        _chart = State(initialValue: chart)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, like Bedtime", text: $chart.title)
                    TextField("Emoji", text: Binding(get: { chart.emoji }, set: { chart.emoji = String($0.prefix(2)) }))
                }
                Section("Who") {
                    KidsToggle(kidIDs: $chart.kidIDs)
                }
                Section("Steps") {
                    ForEach(chart.steps.indices, id: \.self) { index in
                        HStack {
                            TextField("🙂", text: Binding(get: { chart.steps[index].emoji },
                                                          set: { chart.steps[index].emoji = String($0.prefix(2)) }))
                                .frame(width: 44)
                            TextField("Step", text: Binding(get: { chart.steps[index].title }, set: { chart.steps[index].title = $0 }))
                        }
                    }
                    .onDelete { chart.steps.remove(atOffsets: $0) }
                    .onMove { chart.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        chart.steps.append(ChartStep(emoji: "⭐️", title: ""))
                    } label: {
                        Label("Add a step", systemImage: "plus")
                    }
                }
                if !isNew {
                    Section {
                        Button("Delete chart", role: .destructive) {
                            model.deleteChart(chart.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New chart" : chart.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = chart
                        saved.steps.removeAll { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                        model.saveChart(saved)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(chart.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
