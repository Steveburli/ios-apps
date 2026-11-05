import SwiftUI
import OMMKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false
    @State private var pickingStretches = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 14) {
                header
                StatsCard(program: model.program)
                QuickLogCard()
                Card(padding: 6) {
                    MuscleGrid()
                }
                setupCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .alert("Reset the entire program?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetProgram() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all progress, saved weights and reps, the start date, and daily set history.")
        }
        .sheet(isPresented: $pickingStretches) {
            StretchPickerView()
                .environment(model)
                .presentationDetents([.large])
        }
        .sheet(item: $model.presetSheet) { sheet in
            PresetEditorView(sheet: sheet)
                .environment(model)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("OMM")
                .font(.system(size: 60, weight: .heavy))
                .tracking(6)
                .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
            Text("Old Man Maintenance")
                .font(.headline.weight(.medium))
                .opacity(0.92)
        }
        .foregroundStyle(Color.white)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Workout Duration:")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .padding(.bottom, 10)
                minuteSlider(value: durationBinding, range: WorkoutPlan.durationRange,
                             step: WorkoutPlan.durationStep, label: "Workout duration")
                    .padding(.bottom, 14)

                Divider().overlay(Theme.border)
                Toggle(isOn: cardioOnBinding) {
                    optionLabel("Add cardio at the end", detail: cardioDetail)
                }
                .tint(Theme.primary)
                .padding(.vertical, 12)
                if model.cardioOn {
                    cardioSlider
                        .padding(.bottom, 12)
                }

                Divider().overlay(Theme.border)
                Toggle(isOn: stretchBinding) {
                    optionLabel("Stretch afterwards", detail: stretchDetail)
                }
                .tint(Theme.primary)
                .padding(.vertical, 12)
                .padding(.bottom, 6)

                Button("Start Workout") { model.startWorkout() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canStart)
                Button("Just Stretch") { pickingStretches = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 10)
                Button("Reset Program") { confirmingReset = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private var cardioSlider: some View {
        let maxMinutes = Cardio.maxMinutes(forDuration: model.durationMinutes)
        if maxMinutes > Cardio.minutesRange.lowerBound {
            minuteSlider(value: cardioBinding, range: Cardio.minutesRange.lowerBound...maxMinutes,
                         step: Cardio.minutesStep, label: "Cardio length")
        } else {
            Text("\(model.cardioMinutesForWorkout) min of cardio. Longer workouts allow more.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private func minuteSlider(value: Binding<Double>, range: ClosedRange<Int>, step: Int, label: String) -> some View {
        HStack(spacing: 14) {
            Slider(value: value, in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                .tint(Theme.primary)
                .accessibilityLabel(label)
                .accessibilityValue("\(Int(value.wrappedValue)) minutes")
            Text("\(Int(value.wrappedValue)) min")
                .font(.headline.weight(.heavy).monospacedDigit())
                .foregroundStyle(Theme.primary)
                .frame(minWidth: 62, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func optionLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private var cardioDetail: String {
        guard model.cardioOn else { return "Comes out of your workout time" }
        let cardio = model.cardioMinutesForWorkout
        return "\(model.durationMinutes - cardio) min of sets, then \(cardio) min of cardio"
    }

    private var stretchDetail: String {
        // One pick per section, and sections never share a body area, so no repeats.
        let areas = model.selection.orderedKeys.compactMap { Catalog.group($0)?.area }
        guard !areas.isEmpty else { return "Adds a few minutes for the areas you worked" }
        let minutes = Stretches.minutes(for: Stretches.routine(areas: areas))
        return "Adds about \(minutes.counted("minute")) after your workout"
    }

    private var durationBinding: Binding<Double> {
        Binding(get: { Double(model.durationMinutes) },
                set: { model.durationMinutes = Int($0.rounded()) })
    }

    private var cardioBinding: Binding<Double> {
        Binding(get: { Double(model.cardioMinutesForWorkout) },
                set: { model.cardioMinutes = Int($0.rounded()) })
    }

    private var cardioOnBinding: Binding<Bool> {
        Binding(get: { model.cardioOn }, set: { model.cardioOn = $0 })
    }

    private var stretchBinding: Binding<Bool> {
        Binding(get: { model.stretchAfter }, set: { model.stretchAfter = $0 })
    }
}

struct StatsCard: View {
    let program: ProgramState

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                row("Started:", started)
                Divider().overlay(Theme.border)
                row("Estimated completion:", estimate)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var started: String {
        program.startDate?.formatted(date: .numeric, time: .omitted) ?? "Not started"
    }

    private var estimate: String {
        if program.isComplete { return "Complete!" }
        guard let days = program.estimatedDaysRemaining else { return "-" }
        return days.counted("day")
    }
}
