import SwiftUI
import DoThisNowKit

/// The break bank on the Track tab: the focus timer, the balance, taking a
/// break, and what fits in it.
struct BreakBankCard: View {
    @Environment(AppModel.self) private var model
    @State private var editingIdeas = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(at: context.date)
        }
        .sheet(isPresented: $editingIdeas) {
            BreakIdeasSheet()
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let state = model.state
        let balance = state.breakBalance(at: date, calendar: model.calendar)
        let available = state.breakMinutesAvailable(at: date, calendar: model.calendar)
        VStack(alignment: .leading, spacing: 12) {
            Text("BREAK BANK")
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.ink3)
            Text(BreakText.balance(balance))
                .font(Theme.display(26))
                .foregroundStyle(balance <= -60 ? Theme.warn : Theme.ink)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)

            if let focus = state.breaks.focus {
                focusSection(focus, at: date)
            } else if let current = state.breaks.current {
                breakSection(current, at: date)
            } else {
                Text("Every \(state.settings.workPerBreak) minutes of focus earns 1 minute of break. Timed sessions from the Now tab count too.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                FlowLayout {
                    Button("Start focus") { model.startFocus() }
                        .buttonStyle(.dtn(.primary))
                    takeBreakMenu(available: available)
                    if available >= 1 {
                        Button("Fill my break") { model.fillBreak() }
                            .buttonStyle(.dtn())
                            .accessibilityHint("Starts a \(available)-minute break and picks tasks that fit it")
                    }
                }
            }

            ideas(available: state.breaks.current.map { max(0, Int(($0.endsAt.timeIntervalSince(date) / 60).rounded(.down))) } ?? available)
        }
        .card()
    }

    private func focusSection(_ focus: FocusRun, at date: Date) -> some View {
        let work = model.state.focusWork(at: date)
        let earned = model.state.breakEarned(forWork: work)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Focusing")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(TimeText.clock(work))
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("\(Int(work / 60)) minutes focused")
            }
            Text("+\(BreakText.amount(earned)) of break so far")
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
            if model.state.needsStillWorking(at: date) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Still working? The timer has stopped counting until you say so.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                    FlowLayout {
                        Button("Yes, keep going") { model.confirmStillWorking() }
                            .buttonStyle(.dtn(.primary, size: .small))
                        Button("No, stop the timer") { model.stopFocus() }
                            .buttonStyle(.dtn(size: .small))
                    }
                }
                .banner()
            } else {
                FlowLayout {
                    Button("Stop focus") { model.stopFocus() }
                        .buttonStyle(.dtn())
                    takeBreakMenu(available: model.state.breakMinutesAvailable(at: date, calendar: model.calendar))
                }
            }
        }
    }

    private func breakSection(_ current: BreakRun, at date: Date) -> some View {
        let left = max(0, current.endsAt.timeIntervalSince(date))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("On a break")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.good)
                Spacer()
                Text(TimeText.clock(left) + " left")
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("\(Int(left / 60)) minutes left")
            }
            FlowLayout {
                Button("Back to work") { model.endBreak() }
                    .buttonStyle(.dtn())
                    .accessibilityHint("Ends the break and keeps the time you didn’t use")
                Button("Start focus") { model.startFocus() }
                    .buttonStyle(.dtn(.primary))
            }
        }
    }

    /// Any length works. Going past what's earned puts you in debt, and the
    /// next focus time pays it back.
    private func takeBreakMenu(available: Int) -> some View {
        Menu {
            if available >= 1 {
                Button("All of it (\(TimeText.duration(available)))") { model.startBreak(minutes: available) }
            }
            ForEach([5, 10, 15, 20, 30, 45, 60].filter { $0 != available }, id: \.self) { minutes in
                Button(minutes > available ? "\(TimeText.duration(minutes)) (owe \(TimeText.duration(minutes - available)))"
                                           : TimeText.duration(minutes)) {
                    model.startBreak(minutes: minutes)
                }
            }
        } label: {
            Text("Take a break")
        }
        .menuStyle(.button)
        .buttonStyle(.dtn())
    }

    @ViewBuilder
    private func ideas(available: Int) -> some View {
        let fits = model.state.breakFits(minutes: available)
        VStack(alignment: .leading, spacing: 8) {
            if !fits.isEmpty {
                Text("Enough time for")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                FlowLayout {
                    ForEach(fits, id: \.idea.id) { fit in
                        Label(fit.times > 1 ? "\(fit.times) × \(fit.idea.name)" : fit.idea.name, systemImage: fit.idea.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.surface2, in: Capsule())
                            .accessibilityLabel("\(fit.times > 1 ? "\(fit.times) times " : "")\(fit.idea.name), \(fit.minutes) minutes each")
                    }
                }
            }
            Button("Edit break ideas") { editingIdeas = true }
                .buttonStyle(.dtn(.quiet, size: .small))
        }
    }
}

/// The short list of things to do on a break, each with its usual length.
struct BreakIdeasSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var ideas: [BreakIdea] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($ideas) { $idea in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Name", text: $idea.name)
                            Stepper(value: $idea.minutes, in: 1...240, step: idea.minutes < 10 ? 1 : 5) {
                                Text("\(idea.minutes) min")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Theme.ink2)
                            }
                        }
                    }
                    .onDelete { ideas.remove(atOffsets: $0) }
                    .onMove { ideas.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add an idea") { ideas.append(BreakIdea(name: "", minutes: 10)) }
                } footer: {
                    Text("Shown when your break is long enough. If you time one of these on Track with the same name, your usual time is used instead.")
                }
                Section {
                    Button("Put back the starter list") { ideas = BreakIdea.starters }
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Break ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveBreakIdeas(ideas)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                if !loaded {
                    ideas = model.state.breaks.ideas
                    loaded = true
                }
            }
        }
    }
}

/// The balance on the Now tab, once the break bank is in use. Tapping it
/// opens the Track tab.
struct BreakBalanceBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let breaks = model.state.breaks
        if breaks.focus != nil || breaks.current != nil || breaks.seconds != 0 {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let balance = model.state.breakBalance(at: context.date, calendar: model.calendar)
                Button { model.tab = .track } label: {
                    HStack(spacing: 10) {
                        Image(systemName: breaks.current != nil ? "cup.and.saucer" : breaks.focus != nil ? "timer" : "banknote")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BreakText.balance(balance))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.ink)
                            if breaks.focus != nil {
                                Text("Focus timer running")
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink3)
                            } else if breaks.current != nil {
                                Text("On a break")
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.ink3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the break bank on the Track tab")
            }
        }
    }
}
