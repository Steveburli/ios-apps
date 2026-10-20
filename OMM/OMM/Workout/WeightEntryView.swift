import SwiftUI
import OMMKit

/// Shown after the last set: a weight for each of the ten exercises of every
/// group in the workout, prefilled with the last one entered.
struct WeightEntryView: View {
    @Environment(AppModel.self) private var model
    let groupKeys: [String]
    @State private var entries: [String: String] = [:]
    @FocusState private var focusedKey: String?

    private var groups: [MuscleGroup] {
        groupKeys.compactMap(Catalog.group)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Enter Weights Used")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                    Button("Save & Continue") {
                        focusedKey = nil
                        model.saveWeights(entries)
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
                    Button("Done") { focusedKey = nil }
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
                weightRow(group: group, exercise: exercise)
            }
        }
    }

    private func weightRow(group: MuscleGroup, exercise: String) -> some View {
        let key = ProgramState.weightKey(group: group, exercise: exercise)
        return HStack(spacing: 12) {
            Text("\(group.name) — \(exercise)")
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text("Weight (lbs)")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                TextField("0", text: binding(for: key))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .focused($focusedKey, equals: key)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(width: 92)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(focusedKey == key ? Theme.primary : Theme.border, lineWidth: 1.5)
                    )
                    .accessibilityLabel("\(exercise) weight in pounds")
            }
        }
        .padding(.vertical, 10)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { entries[key] ?? "" }, set: { entries[key] = $0 })
    }

    private func loadEntries() {
        guard entries.isEmpty else { return }
        for group in groups {
            for exercise in group.allExercises {
                let key = ProgramState.weightKey(group: group, exercise: exercise)
                entries[key] = model.program.weights[key] ?? ""
            }
        }
    }
}
