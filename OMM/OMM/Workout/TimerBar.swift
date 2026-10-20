import SwiftUI
import OMMKit

/// The bar pinned to the bottom of a set: progress, clock, and the two buttons.
struct TimerBar: View {
    @Environment(AppModel.self) private var model
    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: session.isResting ? 0.25 : 60)) { context in
            let status = RestStatus(session: session, now: context.date)
            VStack(spacing: 0) {
                ProgressBar(fraction: status.fraction)
                Text(status.clock)
                    .font(.system(size: 46, weight: .heavy).monospacedDigit())
                    .foregroundStyle(status.clockColor)
                    .padding(.top, 8)
                    .accessibilityLabel(status.accessibleClock)
                Text(status.info)
                    .font(.subheadline.weight(status.tone == .done ? .bold : .regular))
                    .foregroundStyle(status.tone == .done ? Theme.success : Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 18)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                HStack(spacing: 10) {
                    if !session.isResting {
                        Button("Start Timer") { model.startRest() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Next Workout") { model.skipToNext() }
                        .buttonStyle(SecondaryButtonStyle())
                }
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
}

private struct ProgressBar: View {
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
        let total = Double(session.plan.restSeconds)
        switch session.rest {
        case .running(let endsAt):
            let left = max(0, endsAt.timeIntervalSince(now))
            let seconds = Int(left.rounded(.up))
            clock = Self.format(seconds)
            accessibleClock = "\(seconds) seconds of rest left"
            info = "Rest time — Get ready for next exercise"
            fraction = total > 0 ? 1 - left / total : 1
            tone = .running
        case .done:
            clock = "0:00"
            accessibleClock = "Rest is over"
            info = "Ready for next set!"
            fraction = 1
            tone = .done
        case .idle:
            clock = Self.format(session.plan.restSeconds)
            accessibleClock = "Rest timer, \(session.plan.restSeconds) seconds"
            info = session.isLastStep ? "Last set! Tap either button when you finish" : "Finish this set, then tap Start Timer"
            fraction = 0
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

    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
