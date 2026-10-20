import SwiftUI
import UIKit
import DoThisNowKit

/// The running timer: a big clock, a meter, and how to wrap up.
struct DoingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.state.active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(session, now: context.date)
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    @ViewBuilder
    private func content(_ session: ActiveSession, now: Date) -> some View {
        let over = session.isOver(at: now)
        let tasks = session.taskIDs.compactMap { model.state.task($0) }
        let recurring = !session.bundle && tasks.first?.kind == .recurring

        VStack(alignment: .leading, spacing: 16) {
            Text(session.pausedAt != nil ? "PAUSED" : over ? "TIME’S UP" : "DOING THIS NOW")
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.ink3)
            Text(session.title)
                .font(Theme.display(34))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(Self.clock(session, now: now))
                .font(.system(size: 96, weight: .medium, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(over ? Theme.accent : Theme.ink)
                .accessibilityLabel(Self.spokenClock(session, now: now))
            GeometryReader { proxy in
                Capsule()
                    .fill(Theme.surface2)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * Self.fraction(session, now: now))
                    }
            }
            .frame(height: 10)
            .animation(.linear(duration: 1), value: Self.fraction(session, now: now))
            .accessibilityHidden(true)

            Text(over
                 ? "You planned \(TimeText.duration(session.planned)). Keep going, or call it here?"
                 : "\(TimeText.duration(session.planned)) planned · started \(model.formats.time(session.startedAt))")
                .foregroundStyle(Theme.ink2)

            if session.bundle {
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        let ticked = session.ticked.contains(task.id)
                        Button {
                            model.tick(taskID: task.id, checked: !ticked)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: ticked ? "checkmark.square.fill" : "square")
                                    .font(.title3)
                                    .foregroundStyle(ticked ? Theme.accent : Theme.ink3)
                                (Text(task.title) + Text(task.place.isEmpty ? "" : " · \(task.place)").foregroundStyle(Theme.ink3).font(.footnote))
                                    .strikethrough(ticked)
                                    .foregroundStyle(ticked ? Theme.ink3 : Theme.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(ticked ? .isSelected : [])
                    }
                }
            }

            VStack(spacing: 10) {
                Button(recurring ? "Done for today" : session.bundle ? "Done" : "Finished it") {
                    model.endSession(finished: !(recurring || session.bundle))
                }
                .buttonStyle(.dtn(.primary, size: .big, wide: true))
                HStack(spacing: 10) {
                    if !(recurring || session.bundle) {
                        Button("Done for now") { model.endSession(finished: false) }
                            .buttonStyle(.dtn(wide: true))
                    }
                    Button(session.pausedAt != nil ? "Resume" : "Pause") {
                        if session.pausedAt != nil {
                            model.resume()
                        } else {
                            model.pause()
                        }
                    }
                    .buttonStyle(.dtn(wide: true))
                }
                HStack(spacing: 10) {
                    Button("+15 min") { model.extend() }
                        .buttonStyle(.dtn(wide: true))
                    Button("Cancel") { model.cancelSession() }
                        .buttonStyle(.dtn(.quiet, wide: true))
                }
            }
        }
        .sensoryFeedback(.success, trigger: session.chimed)
    }

    static func remainingSeconds(_ session: ActiveSession, now: Date) -> Int {
        Int((Double(session.planned * 60) - session.elapsed(at: now)).rounded())
    }

    /// "12:34", "1:02:03", or "+3:10" once over.
    static func clock(_ session: ActiveSession, now: Date) -> String {
        let left = remainingSeconds(session, now: now)
        let s = abs(left)
        let text = s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
        return left < 0 ? "+" + text : text
    }

    static func spokenClock(_ session: ActiveSession, now: Date) -> String {
        let left = remainingSeconds(session, now: now)
        let minutes = abs(left) / 60
        return left < 0 ? "\(minutes) minutes over" : "\(minutes) minutes left"
    }

    static func fraction(_ session: ActiveSession, now: Date) -> Double {
        min(1, max(0, session.elapsed(at: now) / Double(session.planned * 60)))
    }
}
