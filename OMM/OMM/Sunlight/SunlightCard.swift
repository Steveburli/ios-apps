import SwiftUI
import OMMKit

/// The sunlight card on the home screen: today's minutes outside against the
/// goal, the "I'm outside" timer and a 7-day row of small rings.
struct SunlightCard: View {
    @Environment(SunlightModel.self) private var sunlight
    @Environment(\.scenePhase) private var scenePhase

    static let sun = Color(hex: 0xD69E2E)

    var body: some View {
        @Bindable var sunlight = sunlight
        Card {
            TimelineView(.periodic(from: .now, by: sunlight.log.isOutside ? 1 : 60)) { context in
                content(now: context.date)
            }
        }
        .onAppear { sunlight.rescheduleReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sunlight.rescheduleReminders() }
        }
        .sheet(item: $sunlight.sheet) { sheet in
            SunlightLogSheet(mode: sheet)
                .environment(sunlight)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $sunlight.showingSettings) {
            SunlightSettingsView()
                .environment(sunlight)
        }
        .sensoryFeedback(.success, trigger: sunlight.log.entries.count)
    }

    private func content(now: Date) -> some View {
        let log = sunlight.log
        let today = log.minutesToday(now: now)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sunlight")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    sunlight.showingSettings = true
                } label: {
                    Label("Goal & Reminders", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
            }
            HStack(spacing: 16) {
                SunRing(fraction: log.fraction(minutes: today), lineWidth: 10) {
                    VStack(spacing: 0) {
                        Text("\(today)")
                            .font(.title2.weight(.heavy).monospacedDigit())
                            .foregroundStyle(Theme.text)
                        Text("of \(log.goalMinutes) min")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 92, height: 92)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sunlight today")
                .accessibilityValue("\(today) of \(log.goalMinutes) minutes")

                VStack(alignment: .leading, spacing: 8) {
                    Text(status(log: log, today: today, now: now))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if log.isOutside {
                        Button { sunlight.comeInside() } label: {
                            Label("Back inside", systemImage: "house.fill")
                        }
                        .buttonStyle(SunButtonStyle(filled: false))
                    } else {
                        Button { sunlight.goOutside() } label: {
                            Label("I'm outside", systemImage: "sun.max.fill")
                        }
                        .buttonStyle(SunButtonStyle(filled: true))
                        Button("Add time") { sunlight.sheet = .add }
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            weekRow(log: log, now: now)
        }
    }

    private func status(log: SunlightLog, today: Int, now: Date) -> String {
        if let since = log.outsideSince {
            let seconds = Int(now.timeIntervalSince(since))
            return "Outside for \(Clock.string(max(0, seconds))). It keeps counting with the phone locked."
        }
        if today >= log.goalMinutes {
            let streak = log.streak(now: now)
            return streak > 1 ? "Goal met. \(streak) days in a row." : "Goal met for today."
        }
        return "\(log.goalMinutes - today) min to go. Morning light helps most."
    }

    private func weekRow(log: SunlightLog, now: Date) -> some View {
        let days = log.recentDays(7, now: now)
        return HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    SunRing(fraction: log.fraction(minutes: day.minutes), lineWidth: 4) {
                        if day.minutes >= log.goalMinutes {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Self.sun)
                        }
                    }
                    .frame(width: 26, height: 26)
                    Text(day.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Calendar.current.isDate(day.day, inSameDayAs: now) ? Theme.text : Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue("\(day.minutes) of \(log.goalMinutes) minutes")
            }
        }
    }
}

/// A progress ring in the sunlight color.
struct SunRing<Content: View>: View {
    let fraction: Double
    let lineWidth: CGFloat
    @ViewBuilder var label: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(SunlightCard.sun.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(SunlightCard.sun, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(fraction > 0 ? 1 : 0)
            label
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

struct SunButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(filled ? Color.white : SunlightCard.sun)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(filled ? SunlightCard.sun : SunlightCard.sun.opacity(0.12))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
