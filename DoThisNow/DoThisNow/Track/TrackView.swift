import SwiftUI
import DoThisNowKit

/// The Track tab: tap what you're starting, tap it again when you're done.
/// The times teach the Inbox and the Wake plan how long things take.
struct TrackView: View {
    @Environment(AppModel.self) private var model

    private let starters: [(name: String, symbol: String)] = [
        ("Shower", "shower"), ("Get dressed", "tshirt"), ("Breakfast", "fork.knife"), ("Commute to work", "car"),
        ("Dishes", "sink"), ("Laundry", "washer"),
    ]

    var body: some View {
        let activities = model.state.activities
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Track")
                        .font(Theme.display(36))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("+ Add") { model.sheet = .newActivity }
                        .buttonStyle(.dtn(.primary))
                }
                Text("Tap something when you start it and tap it again when you’re done. Tap the next thing to switch. Your times set the estimates in the Inbox and your wake-up time, with odd runs left out.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)

                if let running = model.state.running {
                    RunningCard(running: running)
                }

                if activities.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What do you do often? Start with your morning, so the Wake tab can plan it.")
                            .foregroundStyle(Theme.ink)
                        FlowLayout {
                            ForEach(starters, id: \.name) { starter in
                                Button {
                                    model.save(Activity(name: starter.name, symbol: starter.symbol))
                                } label: {
                                    Label(starter.name, systemImage: starter.symbol)
                                }
                                .buttonStyle(.dtn(size: .small))
                            }
                        }
                    }
                    .card()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(activities) { activity in
                            ActivityTile(activity: activity)
                        }
                    }
                }

                TodayTimings()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The stopwatch that's running, big.
private struct RunningCard: View {
    @Environment(AppModel.self) private var model
    let running: RunningTimer

    var body: some View {
        let usual = model.state.estimate(title: running.title, activityID: running.activityID)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = context.date.timeIntervalSince(running.startedAt)
            VStack(alignment: .leading, spacing: 10) {
                Text("TIMING")
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.accentInk.opacity(0.8))
                Text(running.title)
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.accentInk)
                Text(TimeText.clock(seconds))
                    .font(.system(size: 64, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.accentInk)
                    .accessibilityLabel("\(Int(seconds / 60)) minutes \(Int(seconds) % 60) seconds")
                if usual.isFromHistory {
                    Text("Usually \(TimeText.duration(usual.minutes))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentInk.opacity(0.85))
                }
                Button("Stop") { model.stopTimer() }
                    .buttonStyle(.dtn(size: .regular, wide: true))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// One thing you time. Tap to start, tap again to stop.
private struct ActivityTile: View {
    @Environment(AppModel.self) private var model
    let activity: Activity

    var body: some View {
        let isRunning = model.state.running?.activityID == activity.id
        let estimate = model.state.estimate(title: activity.name, activityID: activity.id)
        let count = model.state.timings(for: activity.name, activityID: activity.id).count
        Button {
            model.tapActivity(activity.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: activity.symbol)
                        .font(.title3)
                    Spacer()
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.caption.weight(.bold))
                }
                Text(activity.name)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(count == 0 ? "Not timed yet" : "Usually \(TimeText.duration(estimate.minutes)) · \(count) time\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .opacity(0.8)
            }
            .foregroundStyle(isRunning ? Theme.accentInk : Theme.ink)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(isRunning ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isRunning ? Theme.accent : Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: isRunning)
        .contextMenu {
            Button("History and details", systemImage: "chart.bar") { model.sheet = .activity(activity.id) }
            Button("Add a time you forgot", systemImage: "plus") { model.sheet = .newTiming(activity.id) }
        }
        .accessibilityLabel(activity.name)
        .accessibilityValue(isRunning ? "Timing" : count == 0 ? "Not timed yet" : "Usually \(TimeText.duration(estimate.minutes))")
        .accessibilityHint(isRunning ? "Stops and saves the time" : "Starts timing it")
        .accessibilityAction(named: "History and details") { model.sheet = .activity(activity.id) }
    }
}

/// Everything timed today, newest first.
private struct TodayTimings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let start = model.calendar.startOfDay(for: model.now)
        let today = model.state.timings.filter { $0.start >= start }.sorted { $0.start > $1.start }
        if !today.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                ForEach(today) { timing in
                    TimingRow(timing: timing)
                }
            }
            .padding(.top, 6)
        }
    }
}

struct TimingRow: View {
    @Environment(AppModel.self) private var model
    let timing: Timing
    var showsDate = false

    var body: some View {
        let f = model.formats
        Button { model.sheet = .timing(timing.id) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timing.title).font(.subheadline).foregroundStyle(Theme.ink)
                    Text((showsDate ? f.shortDate(timing.start) + ", " : "") + "\(f.time(timing.start))–\(f.time(timing.end))")
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                Text(TimeText.clock(timing.seconds))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit or delete this time")
    }
}
