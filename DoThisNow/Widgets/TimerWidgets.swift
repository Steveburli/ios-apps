import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Timeline

struct TimerEntry: TimelineEntry {
    let date: Date
    let snapshot: TimerBridge.Snapshot
}

/// One entry, redrawn whenever the app or a button changes the timers. The
/// elapsed time counts on its own with `Text(_:style: .timer)`.
struct TimerProvider: TimelineProvider {
    static let sample = TimerBridge.Snapshot(
        running: TimerBridge.Run(activityID: "shower", title: "Shower", symbol: "shower",
                                 startedAt: Date().addingTimeInterval(-7 * 60)),
        buttons: [
            TimerBridge.StartButton(id: "shower", name: "Shower", symbol: "shower"),
            TimerBridge.StartButton(id: "dressed", name: "Get dressed", symbol: "tshirt"),
            TimerBridge.StartButton(id: "breakfast", name: "Breakfast", symbol: "fork.knife"),
            TimerBridge.StartButton(id: "commute", name: "Commute to work", symbol: "car"),
        ],
        ready: true)

    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        let saved = TimerBridge.snapshot()
        completion(TimerEntry(date: Date(), snapshot: context.isPreview && !saved.ready ? Self.sample : saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        completion(Timeline(entries: [TimerEntry(date: Date(), snapshot: TimerBridge.snapshot())], policy: .never))
    }
}

// MARK: - Timer widget

/// The running Track timer with a Stop button, or a button that starts your
/// first pick. Home Screen (small) and Lock Screen.
struct TimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoThisNowTimer", provider: TimerProvider()) { entry in
            TimerWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetTheme.bg }
        }
        .configurationDisplayName("Timer")
        .description("Shows the Track timer that’s running, with a Stop button. When nothing is running, it starts your first pick from Settings.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: TimerBridge.Snapshot

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    private var first: TimerBridge.StartButton? { snapshot.buttons.first }

    // Home Screen, small.
    @ViewBuilder private var small: some View {
        if let run = snapshot.running {
            VStack(alignment: .leading, spacing: 4) {
                Label("TIMING", systemImage: run.symbol)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(WidgetTheme.accent)
                Text(run.title)
                    .font(WidgetTheme.display(17))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                Text(run.startedAt, style: .timer)
                    .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(WidgetTheme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(intent: StopTrackTimerIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WidgetTheme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let first {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTHING RUNNING")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(WidgetTheme.ink2)
                Spacer(minLength: 0)
                Button(intent: ToggleTrackTimerIntent(activityID: first.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: first.symbol)
                            .font(.title2)
                        Text(first.name)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Label("Start", systemImage: "play.fill")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(WidgetTheme.accentInk)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WidgetTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyPrompt(ready: snapshot.ready)
        }
    }

    // Lock Screen, round: one tap starts your first pick or stops what's running.
    @ViewBuilder private var circular: some View {
        if let run = snapshot.running {
            Button(intent: StopTrackTimerIntent()) {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: "stop.fill")
                            .font(.caption2)
                        Text(run.startedAt, style: .timer)
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop \(run.title)")
        } else if let first {
            Button(intent: ToggleTrackTimerIntent(activityID: first.id)) {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: first.symbol)
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start \(first.name)")
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "stopwatch")
                    .font(.title3)
            }
            .accessibilityLabel("Do This Now timer")
        }
    }

    // Lock Screen, rectangle.
    @ViewBuilder private var rectangular: some View {
        if let run = snapshot.running {
            Button(intent: StopTrackTimerIntent()) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Label(run.title, systemImage: run.symbol)
                            .font(.headline)
                            .lineLimit(1)
                        Text(run.startedAt, style: .timer)
                            .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "stop.circle.fill")
                        .font(.title)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop \(run.title)")
        } else if let first {
            Button(intent: ToggleTrackTimerIntent(activityID: first.id)) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Label(first.name, systemImage: first.symbol)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Tap to start")
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                }
            }
            .buttonStyle(.plain)
        } else {
            Label("No timer running", systemImage: "stopwatch")
                .font(.headline)
        }
    }

    // Lock Screen, the line above the clock (not tappable).
    @ViewBuilder private var inline: some View {
        if let run = snapshot.running {
            Label {
                Text("\(run.title) ") + Text(run.startedAt, style: .timer)
            } icon: {
                Image(systemName: run.symbol)
            }
        } else {
            Label("No timer running", systemImage: "stopwatch")
        }
    }
}

// MARK: - Start buttons widget

/// The activities picked in Settings, one tap each to start or stop.
struct StartButtonsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoThisNowStartButtons", provider: TimerProvider()) { entry in
            StartButtonsView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetTheme.bg }
        }
        .configurationDisplayName("Start buttons")
        .description("Start or stop the Track timers you picked in Settings, without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StartButtonsView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: TimerBridge.Snapshot

    var body: some View {
        let count = family == .systemMedium ? 4 : 2
        let buttons = Array(snapshot.buttons.prefix(count))
        if buttons.isEmpty {
            EmptyPrompt(ready: snapshot.ready)
        } else {
            // Rows of one (small) or two (medium). Widgets can't use lazy grids.
            let perRow = family == .systemMedium ? 2 : 1
            let rows = stride(from: 0, to: buttons.count, by: perRow).map { Array(buttons[$0..<min($0 + perRow, buttons.count)]) }
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        ForEach(rows[index]) { button in
                            StartTile(button: button, running: snapshot.running?.activityID == button.id ? snapshot.running : nil)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One start button. Like the Track tab's tiles: orange while it's timing.
private struct StartTile: View {
    let button: TimerBridge.StartButton
    let running: TimerBridge.Run?

    var body: some View {
        let isRunning = running != nil
        Button(intent: ToggleTrackTimerIntent(activityID: button.id)) {
            HStack(spacing: 6) {
                Image(systemName: button.symbol)
                    .font(.subheadline)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(button.name)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    if let running {
                        Text(running.startedAt, style: .timer)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(isRunning ? WidgetTheme.accentInk : WidgetTheme.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: .infinity, alignment: .leading)
            .background(isRunning ? WidgetTheme.accent : WidgetTheme.surface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isRunning ? WidgetTheme.accent : WidgetTheme.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRunning ? "Stop \(button.name)" : "Start \(button.name)")
    }
}

/// Nothing to show yet.
private struct EmptyPrompt: View {
    let ready: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "stopwatch")
                .font(.title2)
                .foregroundStyle(WidgetTheme.accent)
            Text(ready ? "Pick start buttons in Do This Now’s Settings." : "Open Do This Now to set up your timers.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
