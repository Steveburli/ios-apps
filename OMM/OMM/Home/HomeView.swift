import SwiftUI
import OMMKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                StatsCard(program: model.program)
                Card(padding: 6) {
                    MuscleGrid()
                }
                durationCard
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
            Text("This clears all progress, saved weights, the start date, and daily set history.")
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

    private var durationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Workout Duration:")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .padding(.bottom, 10)
                HStack(spacing: 14) {
                    Slider(value: durationBinding,
                           in: Double(WorkoutPlan.durationRange.lowerBound)...Double(WorkoutPlan.durationRange.upperBound),
                           step: Double(WorkoutPlan.durationStep))
                        .tint(Theme.primary)
                        .accessibilityLabel("Workout duration")
                        .accessibilityValue("\(model.durationMinutes) minutes")
                    Text("\(model.durationMinutes) min")
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(Theme.primary)
                        .frame(minWidth: 62, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 18)

                Button("Start Workout") { model.startWorkout() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canStart)
                Button("Reset Program") { confirmingReset = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 10)
            }
        }
    }

    private var durationBinding: Binding<Double> {
        Binding(get: { Double(model.durationMinutes) },
                set: { model.durationMinutes = Int($0.rounded()) })
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
