import SwiftUI
import OMMKit

/// The bar pinned to the bottom of a set: progress, the clock with its plus
/// and minus buttons, and the two buttons.
struct TimerBar: View {
    @Environment(AppModel.self) private var model
    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: session.isResting ? 0.25 : 15)) { context in
            let status = RestStatus(session: session, now: context.date)
            BottomPanel {
                ProgressBar(fraction: status.fraction)
                HStack(spacing: 16) {
                    adjustButton(-WorkoutSession.restStep, systemImage: "minus", label: "15 seconds less rest")
                        .disabled(session.restSeconds == 0)
                    Text(status.clock)
                        .font(.system(size: 46, weight: .heavy).monospacedDigit())
                        .foregroundStyle(status.clockColor)
                        .frame(minWidth: 130)
                        .accessibilityLabel(status.accessibleClock)
                    adjustButton(WorkoutSession.restStep, systemImage: "plus", label: "15 seconds more rest")
                }
                .padding(.top, 8)
                Text(status.info)
                    .font(.subheadline.weight(status.tone == .done ? .bold : .regular))
                    .foregroundStyle(status.tone == .done ? Theme.success : Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 18)
                    .padding(.top, 4)
                if session.restAdjustment != 0 {
                    adjustedLine(now: context.date)
                        .padding(.top, 6)
                }
                HStack(spacing: 10) {
                    if !session.isResting {
                        Button("Start Timer") { model.startRest() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Next Workout") { model.skipToNext() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 12)
            }
        }
    }

    private func adjustButton(_ delta: Int, systemImage: String, label: String) -> some View {
        Button {
            session.adjustRest(by: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 48, height: 48)
                .background(Theme.primary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// "Rest 2:45 · Done about 6:42 PM · Reset", shown once the rest is changed.
    private func adjustedLine(now: Date) -> some View {
        let finish = session.estimatedFinish(now: now).formatted(date: .omitted, time: .shortened)
        return HStack(spacing: 8) {
            Text("Rest \(Clock.string(session.restSeconds)) · Done about \(finish)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.text)
            Button("Reset") { session.resetRest() }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.primary)
                .accessibilityLabel("Reset to suggested rest, \(Clock.string(session.plan.restSeconds))")
        }
    }
}

/// The white panel pinned to the bottom of the workout, cardio and stretch screens.
struct BottomPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 568)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: Theme.shadow.opacity(0.25), radius: 14, y: -8)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.border)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.primary, Theme.deep], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * min(1, max(0, fraction)))
                }
                .clipShape(Capsule())
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.25), value: fraction)
        .accessibilityHidden(true)
    }
}

/// What the bar shows for the current rest state.
@MainActor
private struct RestStatus {
    enum Tone { case idle, running, done }

    let clock: String
    let accessibleClock: String
    let info: String
    let fraction: Double
    let tone: Tone

    init(session: WorkoutSession, now: Date) {
        fraction = session.rest.fraction(now: now)
        switch session.rest.state {
        case .running:
            let seconds = session.rest.secondsLeft(now: now) ?? 0
            clock = Clock.string(seconds)
            accessibleClock = "\(seconds) seconds of rest left"
            info = "Rest time — Get ready for next exercise"
            tone = .running
        case .done:
            clock = "0:00"
            accessibleClock = "Rest is over"
            info = "Ready for next set!"
            tone = .done
        case .idle:
            clock = Clock.string(session.restSeconds)
            accessibleClock = "Rest timer, \(session.restSeconds) seconds"
            info = session.isLastStep ? "Last set! Tap either button when you finish" : "Finish this set, then tap Start Timer"
            tone = .idle
        }
    }

    var clockColor: Color {
        switch tone {
        case .idle: return Theme.text
        case .running: return Theme.primary
        case .done: return Theme.success
        }
    }
}
