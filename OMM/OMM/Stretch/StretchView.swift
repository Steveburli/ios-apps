import SwiftUI
import UIKit
import OMMKit

/// One stretch at a time: what to do, then a countdown for the hold.
struct StretchView: View {
    @Environment(AppModel.self) private var model
    let session: StretchSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    model.endStretch()
                } label: {
                    Label(session.afterWorkout ? "Done Stretching" : "Back to Home", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.vertical, 6)
                }
                header
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(session.step.stretch.how)
                            .font(.body)
                            .foregroundStyle(Theme.text)
                        Label("Hold \(session.step.stretch.holdSeconds) seconds", systemImage: "timer")
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
            Text("STRETCH · \(session.step.stretch.area.uppercased())")
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
                .accessibilityLabel("Stretch \(session.index + 1) of \(session.steps.count)")
        }
        .shadow(color: Theme.shadow.opacity(0.3), radius: 14, y: 10)
        .accessibilityElement(children: .combine)
    }

    private var bar: some View {
        let timer = session.timer
        return TimelineView(.periodic(from: .now, by: timer.isRunning ? 0.25 : 60)) { context in
            BottomPanel {
                ProgressBar(fraction: timer.fraction(now: context.date))
                Text(clock(now: context.date))
                    .font(.system(size: 46, weight: .heavy).monospacedDigit())
                    .foregroundStyle(timer.state == .done ? Theme.success : (timer.isRunning ? Theme.primary : Theme.text))
                    .padding(.top, 8)
                    .padding(.bottom, 12)
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

    private func clock(now: Date) -> String {
        switch session.timer.state {
        case .idle: return Clock.string(session.step.stretch.holdSeconds)
        case .done: return "0:00"
        case .running: return Clock.string(session.timer.secondsLeft(now: now) ?? 0)
        }
    }
}

/// "Just Stretch" from the home screen: pick body areas, then start.
struct StretchPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Set(Catalog.areas)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pick the areas to stretch. Each stretch is a \(Stretches.holdSeconds)-second hold, both sides where it applies.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    VStack(spacing: 0) {
                        ForEach(Array(Catalog.areas.enumerated()), id: \.element) { index, area in
                            if index > 0 { Divider().overlay(Theme.border) }
                            areaRow(area)
                        }
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button(startTitle) {
                        let areas = Catalog.areas.filter(chosen.contains)
                        dismiss()
                        model.startStretch(areas: areas)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(chosen.isEmpty)
                }
                .padding(16)
            }
            .background(Theme.sheet.ignoresSafeArea())
            .navigationTitle("Just Stretch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var startTitle: String {
        let minutes = Stretches.minutes(for: Stretches.routine(areas: Array(chosen)))
        return chosen.isEmpty ? "Start Stretching" : "Start Stretching (about \(minutes.counted("minute")))"
    }

    private func areaRow(_ area: String) -> some View {
        let on = chosen.contains(area)
        return Button {
            if on { chosen.remove(area) } else { chosen.insert(area) }
        } label: {
            HStack {
                Text(area)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.primary : Theme.border)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
