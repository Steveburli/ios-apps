import Foundation
import Observation
import OMMKit

/// A stretch routine in progress, one hold at a time.
@Observable
@MainActor
final class StretchSession {
    let steps: [StretchStep]
    /// A saved routine's name, or nil for the automatic and after-workout ones.
    let title: String?
    /// True when it follows a workout, so a just-finished program shows its
    /// completion screen afterwards.
    let afterWorkout: Bool
    let timer = Countdown()
    private(set) var index = 0

    init(steps: [StretchStep], title: String? = nil, afterWorkout: Bool) {
        self.steps = steps
        self.title = title
        self.afterWorkout = afterWorkout
    }

    var step: StretchStep {
        steps[index]
    }

    /// The hold after this one, for the "Next up" preview.
    var nextStep: StretchStep? {
        isLast ? nil : steps[index + 1]
    }

    var isLast: Bool {
        index >= steps.count - 1
    }

    /// "3 / 11"
    var progressLabel: String {
        "\(index + 1) / \(steps.count)"
    }

    func startHold() {
        let body = nextStep.map { "Next up: \($0.title)." } ?? "That was the last one."
        timer.start(seconds: step.holdSeconds, title: "Stretch done", body: body)
    }

    func next() {
        timer.cancel()
        if !isLast { index += 1 }
    }

    func stop() {
        timer.cancel()
    }

    func refresh(now: Date = Date()) {
        timer.refresh(now: now)
    }
}
