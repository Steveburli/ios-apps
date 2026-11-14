import SwiftUI
import UIKit
import OMMKit

/// One stretch at a time: a picture and what to do, then a big countdown for
/// the hold, with a chime and a buzz at the end and the next move shown below.
struct StretchView: View {
    @Environment(AppModel.self) private var model
    let session: StretchSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    model.endStretch()
                } label: {
                    Label(session.afterWorkout ? "Done Stretching" : "Back to Stretch", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.vertical, 6)
                }
                header
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        StretchFigureView(stretchID: session.step.stretch.id)
                            .frame(maxWidth: 220)
                            .frame(maxWidth: .infinity)
                        Text(session.step.stretch.how)
                            .font(.body)
                            .foregroundStyle(Theme.text)
                        Label("Hold \(session.step.holdSeconds) seconds", systemImage: "timer")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                        Divider().overlay(Theme.border)
                        Label(Stretches.safetyNote, systemImage: "heart")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bar
        }
        .sensoryFeedback(.success, trigger: session.timer.endedCount)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(.caption.weight(.heavy))
                .tracking(1)
                .opacity(0.85)
            Text(session.step.stretch.name)
                .font(.system(size: 30, weight: .heavy))
                .padding(.trailing, 56)
            if let side = session.step.side {
                Text(side)
                    .font(.headline.weight(.medium))
                    .opacity(0.92)
            }
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.lower, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.3)))
        .overlay(alignment: .topTrailing) {
            Text(session.progressLabel)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2), in: Capsule())
                .padding(14)
                .accessibilityLabel("Move \(session.index + 1) of \(session.steps.count)")
        }
        .shadow(color: Theme.shadow.opacity(0.3), radius: 14, y: 10)
        .accessibilityElement(children: .combine)
    }

    /// "YOGA · THIGHS", or the routine's name first when it has one.
    private var kicker: String {
        let stretch = session.step.stretch
        let parts = [session.title, stretch.kind.title, stretch.area].compactMap { $0 }
        return parts.joined(separator: " · ").uppercased()
    }

    private var bar: some View {
        let timer = session.timer
        return TimelineView(.periodic(from: .now, by: timer.isRunning ? 0.25 : 60)) { context in
            BottomPanel {
                ProgressBar(fraction: timer.fraction(now: context.date))
                Text(clock(now: context.date))
                    .font(.system(size: 76, weight: .heavy).monospacedDigit())
                    .foregroundStyle(timer.state == .done ? Theme.success : (timer.isRunning ? Theme.primary : Theme.text))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 6)
                    .accessibilityLabel(accessibleClock(now: context.date))
                nextUp
                    .padding(.bottom, 10)
                HStack(spacing: 10) {
                    switch timer.state {
                    case .idle:
                        Button("Start Hold") { session.startHold() }
                            .buttonStyle(PrimaryButtonStyle())
                        skipButton
                    case .running:
                        skipButton
                    case .done:
                        Button(session.isLast ? "Finish" : "Next Stretch") { nextOrFinish() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nextUp: some View {
        if let next = session.nextStep {
            HStack(spacing: 8) {
                StretchFigureView(stretchID: next.stretch.id, color: Theme.muted)
                    .frame(width: 30, height: 30)
                Text("Next up: \(next.title)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Last one")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .frame(height: 30)
        }
    }

    private var skipButton: some View {
        Button(session.isLast ? "Finish" : "Skip") { nextOrFinish() }
            .buttonStyle(SecondaryButtonStyle())
    }

    private func nextOrFinish() {
        if session.isLast {
            model.endStretch()
        } else {
            session.next()
        }
    }

    private func seconds(now: Date) -> Int {
        switch session.timer.state {
        case .idle: return session.step.holdSeconds
        case .done: return 0
        case .running: return session.timer.secondsLeft(now: now) ?? 0
        }
    }

    private func clock(now: Date) -> String {
        Clock.string(seconds(now: now))
    }

    private func accessibleClock(now: Date) -> String {
        "\(seconds(now: now).counted("second")) left"
    }
}
