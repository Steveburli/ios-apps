import SwiftUI
import UIKit
import OMMKit

/// One set: the body area, the exercises to choose from, and the rest timer
/// pinned to the bottom.
struct WorkoutView: View {
    @Environment(AppModel.self) private var model
    let session: WorkoutSession
    @State private var confirmingExit = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        confirmingExit = true
                    } label: {
                        Label("Back to Home", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.vertical, 6)
                    }
                    .id("top")

                    if let group = session.group {
                        header(group)
                        ExerciseSection(title: "No Equipment", tint: Theme.primary, group: group,
                                        exercises: group.noEquipment)
                        ExerciseSection(title: "Gym / Equipment", tint: Theme.deep, group: group,
                                        exercises: group.gym)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: session.index) {
                proxy.scrollTo("top", anchor: .top)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TimerBar(session: session)
        }
        .sensoryFeedback(.success, trigger: session.rest.endedCount)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("End this workout?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("End Workout", role: .destructive) { model.endWorkoutEarly() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Sets from this workout won't be saved.")
        }
    }

    private func header(_ group: MuscleGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.category.title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1)
                .opacity(0.85)
            Text(group.area)
                .font(.system(size: 32, weight: .heavy))
                .padding(.trailing, 56)
            Text("\(group.name) — Set \(session.step.set) of \(WorkoutPlan.setsPerGroup)")
                .font(.headline.weight(.medium))
                .opacity(0.92)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(group.category.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.3)))
        .overlay(alignment: .topTrailing) {
            Text(session.progressLabel)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2), in: Capsule())
                .padding(14)
                .accessibilityLabel("Step \(session.index + 1) of \(session.plan.steps.count)")
        }
        .shadow(color: Theme.shadow.opacity(0.3), radius: 14, y: 10)
        .accessibilityElement(children: .combine)
    }
}

/// A numbered list of five exercises under a colored heading. With a muscle
/// group, each row shows your last weight and reps and a suggested weight.
struct ExerciseSection: View {
    @Environment(AppModel.self) private var model
    let title: String
    let tint: Color
    var group: MuscleGroup?
    let exercises: [String]

    var body: some View {
        VStack(spacing: 0) {
            Text(title.uppercased())
                .font(.footnote.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(tint)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                if index > 0 {
                    Divider().overlay(Theme.border)
                }
                row(number: index + 1, exercise: exercise)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.18), radius: 12, y: 8)
    }

    private func row(number: Int, exercise: String) -> some View {
        let text = ExerciseText.split(exercise)
        let lift = group.flatMap { model.program.lift(for: $0, exercise: exercise) }
        let lastWeight = group.flatMap { model.program.weight(for: $0, exercise: exercise) }
        return HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Theme.labelBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    if let note = text.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    if let lift, !lift.reps.isEmpty || lift.tooHeavy {
                        Text(lastLine(lift))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .padding(.top, 2)
                    }
                }
                .accessibilityElement(children: .combine)
                if let group, let lift, let advice = WeightAdvice(log: lift) {
                    AdviceChip(advice: advice, key: ProgramState.weightKey(group: group, exercise: exercise))
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if lift == nil, let lastWeight {
                Text("Last: \(lastWeight) lbs")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.primary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// "Last: 35 lbs × 12, 10, 9" or "Last: 35 lbs, too heavy".
    private func lastLine(_ lift: LiftLog) -> String {
        var line = "Last: \(lift.weight) lbs"
        if !lift.reps.isEmpty {
            line += " × " + lift.reps.map(String.init).joined(separator: ", ")
        }
        if lift.tooHeavy {
            line += ", too heavy"
        }
        return line
    }
}

/// The suggested weight. A tap fills it into the weight sheet for this workout;
/// a second tap takes it back out.
private struct AdviceChip: View {
    @Environment(AppModel.self) private var model
    let advice: WeightAdvice
    let key: String

    var body: some View {
        let chosen = model.session?.plannedWeights[key] == advice.weightText
        VStack(alignment: .leading, spacing: 4) {
            Button {
                model.session?.toggleWeight(advice.weightText, forKey: key)
            } label: {
                Label(chosen ? "\(advice.weightText) lbs set for today" : advice.label,
                      systemImage: chosen ? "checkmark.circle.fill" : icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(chosen ? Color.white : color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(chosen ? color : color.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(chosen ? "Takes it back out of the weight sheet" : "Fills it into the weight sheet for today")
            Text(advice.reason)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
    }

    private var icon: String {
        switch advice.direction {
        case .up: return "arrow.up.circle.fill"
        case .same: return "equal.circle.fill"
        case .down: return "arrow.down.circle.fill"
        }
    }

    private var color: Color {
        switch advice.direction {
        case .up: return Theme.success
        case .same: return Theme.primary
        case .down: return Theme.core
        }
    }
}
