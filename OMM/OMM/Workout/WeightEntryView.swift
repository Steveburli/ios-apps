import SwiftUI
import OMMKit

/// Shown after the sets (and any cardio): a weight for each of the ten
/// exercises of every group in the workout, prefilled with a weight picked
/// from a suggestion or else the last one entered. Rows with a weight also
/// take reps for each set and a "too heavy" tick.
struct WeightEntryView: View {
    @Environment(AppModel.self) private var model
    let session: WorkoutSession
    @State private var weights: [String: String] = [:]
    @State private var reps: [String: [String]] = [:]
    @State private var tooHeavy: Set<String> = []
    @FocusState private var focusedField: String?

    private var groups: [MuscleGroup] {
        session.plan.groupKeys.compactMap(Catalog.group)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Text("Enter Weights Used")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(Theme.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Add the reps for each set of what you did. Tick Too heavy if your form slipped, even if you hit the reps.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 4)
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                    Button("Save & Continue") {
                        focusedField = nil
                        model.saveWeights(weights, reps: parsedReps, tooHeavy: tooHeavy)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.sheet.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear(perform: loadEntries)
    }

    private func groupCard(_ group: MuscleGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(group.area) — \(group.name)")
                .font(.title3.weight(.heavy))
                .foregroundStyle(Theme.text)
                .padding(.top, 12)
                .padding(.bottom, 2)
            subsection("No Equipment", tint: Theme.primary, group: group, exercises: group.noEquipment)
            subsection("Gym / Equipment", tint: Theme.deep, group: group, exercises: group.gym)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 5, y: 2)
    }

    private func subsection(_ title: String, tint: Color, group: MuscleGroup, exercises: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(tint)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(exercises, id: \.self) { exercise in
                Divider().overlay(Theme.border)
                exerciseRow(group: group, exercise: exercise)
            }
        }
    }

    private func exerciseRow(group: MuscleGroup, exercise: String) -> some View {
        let key = ProgramState.weightKey(group: group, exercise: exercise)
        let hasWeight = !(weights[key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("\(group.name) — \(exercise)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Weight (lbs)")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    numberField("0", text: weightBinding(key), field: key, width: 92, decimal: true)
                        .accessibilityLabel("\(exercise) weight in pounds")
                }
            }
            if hasWeight {
                repsRow(key: key, exercise: exercise)
            }
        }
        .padding(.vertical, 10)
    }

    private func repsRow(key: String, exercise: String) -> some View {
        HStack(spacing: 6) {
            Text("Reps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
            ForEach(0..<WorkoutPlan.setsPerGroup, id: \.self) { set in
                numberField("–", text: repsBinding(key, set: set), field: "\(key)#\(set)", width: 44, decimal: false)
                    .accessibilityLabel("\(exercise), set \(set + 1) reps")
            }
            Spacer(minLength: 4)
            let heavy = tooHeavy.contains(key)
            Button {
                if heavy { tooHeavy.remove(key) } else { tooHeavy.insert(key) }
            } label: {
                Label("Too heavy", systemImage: heavy ? "checkmark.square.fill" : "square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(heavy ? Theme.core : Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(exercise) was too heavy")
            .accessibilityAddTraits(heavy ? .isSelected : [])
        }
    }

    private func numberField(_ prompt: String, text: Binding<String>, field: String, width: CGFloat, decimal: Bool) -> some View {
        TextField(prompt, text: text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(decimal ? .trailing : .center)
            .font(.body)
            .foregroundStyle(Theme.text)
            .focused($focusedField, equals: field)
            .padding(.horizontal, decimal ? 10 : 4)
            .padding(.vertical, 9)
            .frame(width: width)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focusedField == field ? Theme.primary : Theme.border, lineWidth: 1.5)
            )
    }

    private func weightBinding(_ key: String) -> Binding<String> {
        Binding(get: { weights[key] ?? "" }, set: { weights[key] = $0 })
    }

    private func repsBinding(_ key: String, set: Int) -> Binding<String> {
        Binding(get: { reps[key]?[set] ?? "" },
                set: { value in
                    var sets = reps[key] ?? Array(repeating: "", count: WorkoutPlan.setsPerGroup)
                    sets[set] = value
                    reps[key] = sets
                })
    }

    /// Typed reps as numbers, blanks dropped.
    private var parsedReps: [String: [Int]] {
        reps.mapValues { sets in
            sets.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
        }
    }

    private func loadEntries() {
        guard weights.isEmpty else { return }
        for group in groups {
            for exercise in group.allExercises {
                let key = ProgramState.weightKey(group: group, exercise: exercise)
                weights[key] = session.plannedWeights[key] ?? model.program.weights[key] ?? ""
            }
        }
    }
}
