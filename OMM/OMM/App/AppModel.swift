import SwiftUI
import Observation
import OMMKit

/// App state: saved progress, the home grid's picks, and the workout in progress.
@Observable
@MainActor
final class AppModel {
    enum Screen: Equatable {
        case home
        case workout
        case complete(days: Int)
    }

    private(set) var program: ProgramState
    private(set) var selection = GroupSelection()
    private(set) var screen: Screen = .home
    private(set) var session: WorkoutSession?
    /// True while the weight sheet is up after the last set.
    var isEnteringWeights = false
    var durationMinutes: Int {
        didSet { defaults.set(durationMinutes, forKey: Keys.duration) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let program = "program.v1"
        static let duration = "durationMinutes"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.program),
           let saved = try? JSONDecoder().decode(ProgramState.self, from: data) {
            program = saved
        } else {
            program = ProgramState()
        }
        let storedDuration = defaults.integer(forKey: Keys.duration)
        durationMinutes = WorkoutPlan.durationRange.contains(storedDuration) ? storedDuration : WorkoutPlan.defaultDuration
    }

    // MARK: Home

    var canStart: Bool {
        !selection.isEmpty
    }

    func toggle(_ group: MuscleGroup) {
        guard !program.isDone(group) else { return }
        selection.toggle(group)
    }

    func startWorkout() {
        let keys = selection.orderedKeys
        guard !keys.isEmpty else { return }
        program.markStarted(at: Date())
        save()
        session = WorkoutSession(plan: WorkoutPlan(groupKeys: keys, durationMinutes: durationMinutes))
        screen = .workout
        RestNotifier.requestPermission()
    }

    func resetProgram() {
        program = ProgramState()
        selection.clear()
        save()
    }

    func goHome() {
        selection.clear()
        screen = .home
    }

    // MARK: Workout

    /// "Start Timer": move to the next set and start resting.
    func startRest() {
        guard let session else { return }
        if session.isLastStep {
            finishWorkout()
        } else {
            session.advance(startingRest: true)
        }
    }

    /// "Next Workout": move to the next set without a timer.
    func skipToNext() {
        guard let session else { return }
        if session.isLastStep {
            finishWorkout()
        } else {
            session.advance(startingRest: false)
        }
    }

    /// Leaves without recording anything.
    func endWorkoutEarly() {
        session?.stop()
        session = nil
        selection.removeCompleted(in: program)
        screen = .home
    }

    private func finishWorkout() {
        guard let session, !session.isFinished else { return }
        session.finish()
        program.recordWorkout(groupKeys: session.plan.groupKeys, setsPerGroup: WorkoutPlan.setsPerGroup,
                              dayKey: DayKey.string(for: Date()))
        save()
        isEnteringWeights = true
    }

    /// "Save & Continue" on the weight sheet.
    func saveWeights(_ entries: [String: String]) {
        for (key, value) in entries {
            program.setWeight(value, forKey: key)
        }
        save()
        isEnteringWeights = false
        session = nil
        selection.clear()
        if program.isComplete {
            screen = .complete(days: DayKey.daysInclusive(from: program.startDate ?? Date(), to: Date()))
        } else {
            screen = .home
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(program) {
            defaults.set(data, forKey: Keys.program)
        }
    }
}
