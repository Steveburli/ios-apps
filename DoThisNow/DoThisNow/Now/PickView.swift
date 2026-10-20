import SwiftUI
import DoThisNowKit

/// "Do this." and the one suggestion, with Start, Already done and Not now.
struct PickView: View {
    @Environment(AppModel.self) private var model
    @State private var popped = false

    private var contextLine: String {
        let c = model.state.context
        var bits = ["\(TimeText.duration(model.available)) free", c.place.label, c.multitasking ? "Multitasking" : "Focused"]
        if c.tv { bits.append("TV on") }
        return bits.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(contextLine)
                .font(.footnote)
                .foregroundStyle(Theme.ink3)
            if let pick = model.currentPick {
                content(pick)
            } else {
                nothingFits
            }
        }
    }

    private var nothingFits: some View {
        let c = model.state.context
        var message = "Nothing on your list works in \(TimeText.duration(model.available)) \(c.place.label.lowercased())"
        if c.multitasking { message += " while multitasking" }
        if c.tv { message += " with the TV on" }
        message += ". Try more time or a different place, or add something that works here."
        return VStack(alignment: .leading, spacing: 18) {
            Text("Nothing fits right now.")
                .font(Theme.hero)
                .foregroundStyle(Theme.ink)
            Text(message)
                .foregroundStyle(Theme.ink2)
            FlowLayout {
                Button("Change my answers") { model.back() }
                    .buttonStyle(.dtn(.primary))
                Button("Add a task") { model.sheet = .newTask }
                    .buttonStyle(.dtn())
            }
        }
    }

    @ViewBuilder
    private func content(_ pick: Candidate) -> some View {
        Text("Do this.")
            .font(Theme.display(88))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(Theme.accent)
            .scaleEffect(popped ? 1 : 0.85)
            .rotationEffect(.degrees(popped ? 0 : -2))
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { popped = true }
            }
            .accessibilityAddTraits(.isHeader)

        PickCard(pick: pick)
            .id(pick.id)

        VStack(spacing: 10) {
            Button("Start") { model.startCurrentPick() }
                .buttonStyle(.dtn(.primary, size: .big, wide: true))
            HStack(spacing: 10) {
                Button("Already done") { model.togglePanel(.done) }
                    .buttonStyle(.dtn(wide: true))
                    .accessibilityValue(model.panel == .done ? "Expanded" : "")
                Button("Not now") { model.togglePanel(.later) }
                    .buttonStyle(.dtn(wide: true))
                    .accessibilityValue(model.panel == .later ? "Expanded" : "")
            }
        }

        if model.panel == .done {
            VStack(alignment: .leading, spacing: 12) {
                Text("When did you do it?").font(.subheadline.weight(.bold))
                FlowLayout {
                    ForEach(DoneWhen.allCases) { when in
                        Chip(title: when.label, isOn: false) { model.markDone(when) }
                    }
                }
                Text("If you don’t remember, I’ll assume about a month ago.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
            }
            .card(padding: 16)
        } else if model.panel == .later {
            VStack(alignment: .leading, spacing: 12) {
                Text("Remind me in…").font(.subheadline.weight(.bold))
                FlowLayout {
                    ForEach(SnoozeChoice.allCases) { choice in
                        Chip(title: choice.label, isOn: false) { model.snooze(choice) }
                    }
                }
                Button("Just show me something else") { model.skipPick() }
                    .font(.subheadline)
                    .underline()
                    .foregroundStyle(Theme.ink2)
            }
            .card(padding: 16)
        }

        HStack(spacing: 6) {
            Button("Change my answers") { model.back() }
                .font(.subheadline)
                .underline()
                .foregroundStyle(Theme.ink2)
            if model.morePicks > 0 && model.panel == nil {
                Text("· \(model.morePicks) more idea\(model.morePicks > 1 ? "s" : "") if you say “Not now”")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }
}

private struct PickCard: View {
    @Environment(AppModel.self) private var model
    let pick: Candidate

    private var timePill: String {
        switch pick.kind {
        case .errands: return "About \(TimeText.duration(pick.minutes)) with driving"
        case .sweep: return "About \(TimeText.duration(pick.minutes))"
        case .task: return pick.finish ? "Finish it · about \(TimeText.duration(pick.minutes))" : "Work on it for \(TimeText.duration(pick.minutes))"
        }
    }

    var body: some View {
        let single = pick.tasks.count == 1 ? pick.tasks.first : nil
        VStack(alignment: .leading, spacing: 14) {
            Text(pick.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            FlowLayout {
                Tag(text: timePill, tone: .hot)
                if let single, !single.place.isEmpty {
                    Tag(text: single.place)
                }
                if let single, single.kind == .recurring {
                    Tag(text: "\(TimeText.duration(model.engine.weekMinutes(single.id))) of \(TimeText.duration(single.weekly)) this week")
                }
            }
            if pick.tasks.count > 1 {
                VStack(spacing: 6) {
                    Divider().overlay(Theme.line)
                    ForEach(pick.tasks) { task in
                        HStack {
                            Text(task.title) + Text(task.place.isEmpty ? "" : " · \(task.place)").foregroundStyle(Theme.ink3).font(.footnote)
                            Spacer()
                            Text(TimeText.duration(task.estimate > 0 ? task.estimate : 15))
                                .font(.footnote)
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                }
            }
            if !pick.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pick.reasons.prefix(3), id: \.self) { reason in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                            Text(reason)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                }
            }
            if let single, !single.notes.isEmpty {
                Text(single.notes)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .card()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
