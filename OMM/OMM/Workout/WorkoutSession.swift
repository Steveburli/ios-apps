import Foundation
import Observation
import OMMKit

/// One workout in progress: which set is on screen and the rest timer.
@Observable
@MainActor
final class WorkoutSession {
    enum Rest: Equatable {
        case idle
        case running(endsAt: Date)
        case done
    }

    let plan: WorkoutPlan
    private(set) var index = 0
    private(set) var rest: Rest = .idle
    private(set) var isFinished = false
    /// Goes up each time rest runs out while the app is open. Drives the haptic.
    private(set) var restEndedCount = 0

    @ObservationIgnored private var restTask: Task<Void, Never>?

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
        if case .running = rest { return true }
        return false
    }

    /// "4 / 9"
    var progressLabel: String {
        "\(index + 1) / \(plan.steps.count)"
    }

    func advance(startingRest: Bool) {
        cancelRest()
        guard !isLastStep else { return }
        index += 1
        if startingRest { beginRest() }
    }

    func finish() {
        cancelRest()
        isFinished = true
    }

    func stop() {
        cancelRest()
    }

    /// Catches up after the app comes back from the background.
    func refresh(now: Date = Date()) {
        if case .running(let endsAt) = rest, now >= endsAt {
            rest = .done
        }
    }

    private func beginRest() {
        let seconds = plan.restSeconds
        guard seconds > 0 else {
            rest = .done
            return
        }
        let endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        rest = .running(endsAt: endsAt)

        let body: String
        if let group {
            body = "Up next: \(group.area) · \(group.name), set \(step.set) of \(WorkoutPlan.setsPerGroup)."
        } else {
            body = "Time for your next set."
        }
        RestNotifier.schedule(after: seconds, title: "Rest is over", body: body)

        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.restEnded(endsAt: endsAt)
        }
    }

    private func restEnded(endsAt: Date) {
        guard rest == .running(endsAt: endsAt) else { return }
        rest = .done
        RestNotifier.cancel()
        // Stay quiet if the timer ran out long ago while the app was suspended.
        if Date().timeIntervalSince(endsAt) < 3 {
            Chime.play()
            restEndedCount += 1
        }
    }

    private func cancelRest() {
        restTask?.cancel()
        restTask = nil
        RestNotifier.cancel()
        rest = .idle
    }
}
