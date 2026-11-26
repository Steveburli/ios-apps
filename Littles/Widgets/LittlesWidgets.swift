import SwiftUI
import WidgetKit
import ActivityKit

@main
struct LittlesWidgets: WidgetBundle {
    var body: some Widget {
        TimerLiveActivity()
    }
}

/// A nap or nursing timer on the Lock Screen and in the Dynamic Island,
/// counting up from when it started. Tapping it opens Littles to stop it.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Text(context.attributes.emoji)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(context.attributes, context.state))
                        .font(.headline)
                    Text("since \(context.state.start.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .opacity(0.8)
                }
                Spacer()
                Text(timerInterval: context.state.start...Date.distantFuture, countsDown: false)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
            .padding(16)
            .foregroundStyle(.white)
            .activityBackgroundTint(color(context.attributes.color))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji).font(.title)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(context.attributes, context.state)).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.start...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .frame(maxWidth: 70)
                }
            } compactLeading: {
                Text(context.attributes.emoji)
            } compactTrailing: {
                Text(timerInterval: context.state.start...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Text(context.attributes.emoji)
            }
            .keylineTint(color(context.attributes.color))
        }
    }

    private func title(_ attributes: TimerActivityAttributes, _ state: TimerActivityAttributes.ContentState) -> String {
        if attributes.activity == "asleep" { return "\(attributes.kidName) is asleep" }
        return "\(attributes.kidName) nursing" + (state.detail.isEmpty ? "" : " · \(state.detail)")
    }

    private func color(_ hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
