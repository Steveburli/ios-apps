import Foundation
import Observation
import OMMKit

/// A stretch routine in progress, one hold at a time.
@Observable
@MainActor
final class StretchSession {
    let steps: [StretchStep]
    /// True when it follows a workout, so a just-finished program shows its
    /// completion screen afterwards.
    let afterWorkout: Bool
    let timer = Countdown()
    private(set) var index = 0

    init(steps: [StretchStep], afterWorkout: Bool) {
        self.steps = steps
        self.afterWorkout = afterWorkout
    }

    var step: StretchStep {
        steps[index]
    }

    var isLast: Bool {
        index >= steps.count - 1
    }

    /// "3 / 11"
    var progressLabel: String {
        "\(index + 1) / \(steps.count)"
    }

    func startHold() {
        let body = isLast ? "That was the last one." : "Next up: \(steps[index + 1].title)."
        timer.start(seconds: step.stretch.holdSeconds, title: "Stretch done", body: body)
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
