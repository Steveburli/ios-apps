import Foundation
import Observation
import OMMKit

/// One workout in progress: which set is on screen, the rest timer, and the
/// cardio block at the end.
@Observable
@MainActor
final class WorkoutSession {
    enum Phase: Equatable {
        case sets
        case cardio
    }

    /// The rest timer's plus and minus buttons move it this many seconds.
    static let restStep = 15
    static let maxExtraRest = 600

    let plan: WorkoutPlan
    let rest = Countdown()
    let cardio = Countdown()
    private(set) var index = 0
    private(set) var phase: Phase = .sets
    private(set) var isFinished = false
    /// Seconds added to or taken off the suggested rest, for this workout only.
    private(set) var restAdjustment = 0
    /// Weights picked from a suggestion before lifting: weight key → pounds.
    /// They prefill the weight sheet.
    private(set) var plannedWeights: [String: String] = [:]

    init(plan: WorkoutPlan) {
        self.plan = plan
    }

    var step: WorkoutPlan.Step {
        plan.steps[index]
    }

    var group: MuscleGroup? {
        Catalog.group(step.groupKey)
    }

    var isLastStep: Bool {
        index >= plan.steps.count - 1
    }

    var isResting: Bool {
        rest.isRunning
    }

    /// The rest to use now: the suggested rest plus any change.
    var restSeconds: Int {
        max(0, plan.restSeconds + restAdjustment)
    }

    /// "4 / 9"
    var progressLabel: String {
        "\(index + 1) / \(plan.steps.count)"
    }

    func advance(startingRest: Bool) {
        rest.cancel()
        guard !isLastStep else { return }
        index += 1
        if startingRest { beginRest() }
    }

    /// Changes the rest for the rest of this workout, including one running now.
    func adjustRest(by delta: Int) {
        let target = min(Self.maxExtraRest, max(-plan.restSeconds, restAdjustment + delta))
        let applied = target - restAdjustment
        guard applied != 0 else { return }
        restAdjustment = target
        rest.adjust(by: applied)
    }

    func resetRest() {
        adjustRest(by: -restAdjustment)
    }

    /// Roughly when everything ends, cardio included, at the current rest.
    func estimatedFinish(now: Date) -> Date {
        var seconds = rest.secondsLeft(now: now) ?? 0
        if phase == .sets {
            seconds += WorkoutPlan.secondsPerSet
                + plan.setsAfter(index) * (restSeconds + WorkoutPlan.secondsPerSet)
                + plan.cardioMinutes * 60
        }
        return now.addingTimeInterval(TimeInterval(seconds))
    }

    /// Fills the weight sheet with a suggested weight, or clears it on a second tap.
    func toggleWeight(_ pounds: String, forKey key: String) {
        plannedWeights[key] = plannedWeights[key] == pounds ? nil : pounds
    }

    /// The sets are done: stop the timer.
    func finish() {
        rest.cancel()
        isFinished = true
    }

    func showCardio() {
        phase = .cardio
    }

    func startCardio() {
        cardio.start(seconds: plan.cardioMinutes * 60, title: "Cardio is done",
                     body: "Nice work. Log your weights next.")
    }

    func stop() {
        rest.cancel()
        cardio.cancel()
    }

    /// Catches up after the app comes back from the background.
    func refresh(now: Date = Date()) {
        rest.refresh(now: now)
        cardio.refresh(now: now)
    }

    private func beginRest() {
        let body: String
        if let group {
            body = "Up next: \(group.area) · \(group.name), set \(step.set) of \(WorkoutPlan.setsPerGroup)."
        } else {
            body = "Time for your next set."
        }
        rest.start(seconds: restSeconds, title: "Rest is over", body: body)
    }
}
