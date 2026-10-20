import SwiftUI
import DoThisNowKit

/// The Now tab: ask a few questions, pick one thing, then time it.
struct NowView: View {
    @Environment(AppModel.self) private var model

    private var screenKey: String {
        if model.state.active != nil { return "doing" }
        if model.state.activeTasks.isEmpty { return "empty" }
        return model.nowStep == .pick ? "pick" : "ask"
    }

    var body: some View {
        ScrollView {
            Group {
                switch screenKey {
                case "doing": DoingView()
                case "empty": EmptyNowView()
                case "pick": PickView()
                default: AskView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .id(screenKey)
        .scrollDismissesKeyboard(.immediately)
    }
}

private struct EmptyNowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What should I do now?")
                .font(Theme.hero)
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 14) {
                Text("Tell me what’s on your plate. Each time you open this, I’ll ask a few quick questions and pick the one thing to do right now.")
                    .foregroundStyle(Theme.ink)
                FlowLayout {
                    Button("Add your first task") { model.sheet = .newTask }
                        .buttonStyle(.dtn(.primary))
                    Button("Try it with example tasks") { model.loadExamples() }
                        .buttonStyle(.dtn())
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.ink3)
                            .frame(minWidth: 14)
                        Text(step)
                            .font(index == steps.count - 1 ? .body.weight(.bold) : .body)
                            .foregroundStyle(index == steps.count - 1 ? Theme.accent : Theme.ink2)
                    }
                }
            }
        }
    }

    private let steps = [
        "How much time do you have?",
        "Where are you doing your work?",
        "Are you multitasking or focused?",
        "Is the TV on?",
        "Do this.",
    ]
}

private struct TimeOption: Identifiable {
    let minutes: Int
    let label: String
    var id: Int { minutes }

    static let all = [
        TimeOption(minutes: 15, label: "15 min"), TimeOption(minutes: 30, label: "30 min"),
        TimeOption(minutes: 60, label: "1 hour"), TimeOption(minutes: 120, label: "2 hours"),
        TimeOption(minutes: 180, label: "3+ hours"),
    ]
}

/// "What should I do now?" and its questions.
struct AskView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        let context = model.state.context
        let boundary = engine.nextBoundary()
        let firstNudge = engine.nudges().first

        VStack(alignment: .leading, spacing: 22) {
            Text("What should I do now?")
                .font(Theme.hero)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)

            if let happening = engine.eventNow() {
                EventNowBanner(event: happening.event, leaveNow: happening.leaveNow)
            }
            ForEach(engine.dueReminders()) { task in
                ReminderCard(task: task)
            }

            Question(title: "How much time do you have?") {
                if let boundary {
                    Chip(title: "Until \(model.formats.time(model.today, boundary.at))",
                         subtitle: "\(TimeText.duration(boundary.minutes)) · \(boundary.label)",
                         isOn: context.timeMinutes == nil) {
                        model.setContext { $0.timeMinutes = nil }
                    }
                }
                ForEach(TimeOption.all) { option in
                    Chip(title: option.label, isOn: context.timeMinutes == option.minutes) {
                        model.setContext { $0.timeMinutes = option.minutes }
                    }
                }
            }
            Question(title: "Where are you doing your work?") {
                ForEach(Place.current, id: \.self) { place in
                    Chip(title: place.label, isOn: context.place == place) {
                        model.setContext { $0.place = place }
                    }
                }
            }
            Question(title: "Are you multitasking or focused?") {
                Chip(title: "Focused", isOn: !context.multitasking) { model.setContext { $0.multitasking = false } }
                Chip(title: "Multitasking", isOn: context.multitasking) { model.setContext { $0.multitasking = true } }
            }
            Question(title: "Are you watching TV?") {
                Chip(title: "No", isOn: !context.tv) { model.setContext { $0.tv = false } }
                Chip(title: "Yes, keep me in this room", isOn: context.tv) { model.setContext { $0.tv = true } }
            }

            MoodSection(context: context)

            Button("Tell me what to do") { model.go() }
                .buttonStyle(.dtn(.primary, size: .big, wide: true))

            if let minutes = engine.cafeSuggestion(context) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("You’ve got **\(TimeText.duration(minutes))** of computer work piled up. Want to take it to a coffee shop or the library?")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                    FlowLayout {
                        Button("Good idea, pick a computer task") { model.cafeGo() }
                            .buttonStyle(.dtn(.primary, size: .small))
                        Button("Not today") { model.cafeDismiss() }
                            .buttonStyle(.dtn(.quiet, size: .small))
                    }
                }
                .banner()
            }
            if let firstNudge {
                NudgeCard(nudge: firstNudge)
            }
        }
        .sensoryFeedback(.selection, trigger: context)
    }
}

private struct MoodSection: View {
    @Environment(AppModel.self) private var model
    let context: NowContext

    private var summary: String {
        var bits: [String] = []
        if context.posture == .sit { bits.append("Sit") }
        if context.posture == .move { bits.append("Move around") }
        if context.outside == .out { bits.append("Get outside") }
        if context.outside == .cozy { bits.append("Stay cozy") }
        return bits.isEmpty ? "Optional" : bits.joined(separator: " · ")
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Theme.line)
            DisclosureGroup(isExpanded: $model.moodOpen) {
                VStack(alignment: .leading, spacing: 18) {
                    Question(title: "Do you feel like sitting, or do you need to move around?") {
                        Chip(title: "Either", isOn: context.posture == .any) { model.setContext { $0.posture = .any } }
                        Chip(title: "Sitting", isOn: context.posture == .sit) { model.setContext { $0.posture = .sit } }
                        Chip(title: "Move around", isOn: context.posture == .move) { model.setContext { $0.posture = .move } }
                    }
                    Question(title: "Get outside, or stay cozy?") {
                        Chip(title: "Either", isOn: context.outside == .any) { model.setContext { $0.outside = .any } }
                        Chip(title: "Get outside", isOn: context.outside == .out) { model.setContext { $0.outside = .out } }
                        Chip(title: "Stay cozy inside", isOn: context.outside == .cozy) { model.setContext { $0.outside = .cozy } }
                    }
                }
                .padding(.top, 14)
            } label: {
                HStack {
                    Text("How are you feeling?")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink3)
                }
            }
            .tint(Theme.ink3)
            .padding(.top, 14)
        }
    }
}
