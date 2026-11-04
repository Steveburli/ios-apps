import SwiftUI
import UIKit
import OMMKit

/// The cardio block after the last set: pick any one from the list, then a
/// countdown for the whole block. The sets are already saved by now.
struct CardioView: View {
    @Environment(AppModel.self) private var model
    let session: WorkoutSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ExerciseSection(title: "No Equipment", tint: Theme.primary, exercises: Cardio.noEquipment)
                ExerciseSection(title: "Gym / Equipment", tint: Theme.deep, exercises: Cardio.gym)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bar
        }
        .sensoryFeedback(.success, trigger: session.cardio.endedCount)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SETS SAVED")
                .font(.caption.weight(.heavy))
                .tracking(1)
                .opacity(0.85)
            Text("Cardio")
                .font(.system(size: 32, weight: .heavy))
            Text("\(session.plan.cardioMinutes) minutes. Pick any one and keep a steady pace.")
                .font(.headline.weight(.medium))
                .opacity(0.92)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.3)))
        .shadow(color: Theme.shadow.opacity(0.3), radius: 14, y: 10)
        .accessibilityElement(children: .combine)
    }

    private var bar: some View {
        let timer = session.cardio
        return TimelineView(.periodic(from: .now, by: timer.isRunning ? 0.25 : 60)) { context in
            BottomPanel {
                ProgressBar(fraction: timer.fraction(now: context.date))
                Text(clock(now: context.date))
                    .font(.system(size: 46, weight: .heavy).monospacedDigit())
                    .foregroundStyle(timer.state == .done ? Theme.success : (timer.isRunning ? Theme.primary : Theme.text))
                    .padding(.top, 8)
                Text(info)
                    .font(.subheadline.weight(timer.state == .done ? .bold : .regular))
                    .foregroundStyle(timer.state == .done ? Theme.success : Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                HStack(spacing: 10) {
                    if timer.state == .idle {
                        Button("Start Cardio") { session.startCardio() }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("Skip Cardio") { model.finishCardio() }
                            .buttonStyle(SecondaryButtonStyle())
                    } else if timer.state == .done {
                        Button("Log Weights") { model.finishCardio() }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Finish Early") { model.finishCardio() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func clock(now: Date) -> String {
        switch session.cardio.state {
        case .idle: return Clock.string(session.plan.cardioMinutes * 60)
        case .done: return "0:00"
        case .running: return Clock.string(session.cardio.secondsLeft(now: now) ?? 0)
        }
    }

    private var info: String {
        switch session.cardio.state {
        case .idle: return "Tap Start Cardio when you're moving"
        case .running: return "Keep going — you can still talk, but only just"
        case .done: return "Cardio done!"
        }
    }
}
