import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// The running timer on the Lock Screen and in the Dynamic Island, in the
/// Track tab's orange. A Track timer counts up and has a Stop button; the Now
/// tab's session counts down (and on past zero, like the app).
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenTimer(kind: context.attributes.kind, state: context.state)
                .activityBackgroundTint(WidgetTheme.accent)
                .activitySystemActionForegroundColor(WidgetTheme.accentInk)
        } dynamicIsland: { context in
            let state = context.state
            let kind = context.attributes.kind
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.title2)
                        .foregroundStyle(WidgetTheme.accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: state)
                        .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(WidgetTheme.accent)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if kind == .track {
                        Button(intent: StopTrackTimerIntent()) {
                            Label("Stop and save", systemImage: "stop.fill")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WidgetTheme.accent)
                    } else {
                        Text(state.pausedRemaining != nil ? "Paused" : "Now · open Do This Now to finish")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .foregroundStyle(WidgetTheme.accent)
            } compactTrailing: {
                TimerText(state: state)
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.accent)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: state.symbol)
                    .foregroundStyle(WidgetTheme.accent)
            }
            .keylineTint(WidgetTheme.accent)
        }
    }
}

/// Counts up for a Track timer, down for a session, or stands still when paused.
private struct TimerText: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        if let remaining = state.pausedRemaining {
            Text(WidgetTheme.clock(remaining))
        } else if let endsAt = state.endsAt {
            Text(endsAt, style: .timer)
                .multilineTextAlignment(.trailing)
        } else {
            Text(state.startedAt, style: .timer)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The Lock Screen banner, like the Track tab's running card.
private struct LockScreenTimer: View {
    let kind: TimerActivityAttributes.Kind
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Label(label, systemImage: state.symbol)
                    .font(.caption.weight(.heavy))
                    .opacity(0.85)
                Text(state.title)
                    .font(WidgetTheme.display(20))
                    .lineLimit(1)
                TimerText(state: state)
                    .font(.system(size: 40, weight: .medium, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if kind == .track {
                Button(intent: StopTrackTimerIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(WidgetTheme.accentInk)
                .accessibilityLabel("Stop \(state.title) and save the time")
            }
        }
        .foregroundStyle(WidgetTheme.accentInk)
        .padding(16)
    }

    private var label: String {
        switch kind {
        case .track: return "TIMING"
        case .session: return state.pausedRemaining != nil ? "PAUSED" : "TIME LEFT"
        }
    }
}
