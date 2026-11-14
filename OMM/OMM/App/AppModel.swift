import SwiftUI
import Observation
import OMMKit

/// App state: saved progress, the home grid's picks, the workout in progress
/// and any stretch routine.
@Observable
@MainActor
final class AppModel {
    enum Screen: Equatable {
        case home
        case workout
        case stretch
        case complete(days: Int)
    }

    /// The preset editor sheet: a new preset, or a saved one to change.
    enum PresetSheet: Identifiable {
        case new
        case edit(Preset)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let preset): return preset.id.uuidString
            }
        }
    }

    /// The bar on the home screen after a one-tap log, with Undo.
    struct QuickLogNote: Equatable {
        let presetName: String
        let sets: Int
        /// Groups this log crossed off.
        let finished: [String]
        /// Progress before the log, for Undo.
        let previous: ProgramState
    }

    private(set) var program: ProgramState
    /// One-tap routines, saved apart from the program so Reset Program keeps them.
    private(set) var presets: [Preset]
    var presetSheet: PresetSheet?
    private(set) var quickLog: QuickLogNote?
    private(set) var selection = GroupSelection()
    private(set) var screen: Screen = .home
    private(set) var session: WorkoutSession?
    private(set) var stretch: StretchSession?
    /// True while the weight sheet is up after the sets (and any cardio).
    var isEnteringWeights = false
    var durationMinutes: Int {
        didSet { defaults.set(durationMinutes, forKey: Keys.duration) }
    }
    var cardioOn: Bool {
        didSet { defaults.set(cardioOn, forKey: Keys.cardioOn) }
    }
    /// The cardio slider's value. `cardioMinutesForWorkout` fits it to the duration.
    var cardioMinutes: Int {
        didSet { defaults.set(cardioMinutes, forKey: Keys.cardioMinutes) }
    }
    var stretchAfter: Bool {
        didSet { defaults.set(stretchAfter, forKey: Keys.stretchAfter) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let program = "program.v1"
        static let duration = "durationMinutes"
        static let cardioOn = "cardioOn"
        static let cardioMinutes = "cardioMinutes"
        static let stretchAfter = "stretchAfter"
        static let presets = "presets.v1"
    }

    init(defaults: UserDefaults = .standard) {
        if Screenshots.isActive {
            // Sample data in a throwaway store, so screenshots never touch real progress.
            let scratch = UserDefaults(suiteName: "screenshots") ?? defaults
            scratch.removePersistentDomain(forName: "screenshots")
            self.defaults = scratch
            program = Screenshots.sampleProgram()
            presets = Screenshots.samplePresets()
            durationMinutes = WorkoutPlan.defaultDuration
            cardioOn = false
            cardioMinutes = Cardio.defaultMinutes
            stretchAfter = true
            openScreenshotScreen()
            return
        }
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.program),
           let saved = try? JSONDecoder().decode(ProgramState.self, from: data) {
            program = saved
        } else {
            program = ProgramState()
        }
        if let data = defaults.data(forKey: Keys.presets),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = saved
        } else {
            presets = []
        }
        let storedDuration = defaults.integer(forKey: Keys.duration)
        durationMinutes = WorkoutPlan.durationRange.contains(storedDuration) ? storedDuration : WorkoutPlan.defaultDuration
        cardioOn = defaults.bool(forKey: Keys.cardioOn)
        let storedCardio = defaults.integer(forKey: Keys.cardioMinutes)
        cardioMinutes = Cardio.minutesRange.contains(storedCardio) ? storedCardio : Cardio.defaultMinutes
        // Stretching is on until it's turned off.
        stretchAfter = defaults.object(forKey: Keys.stretchAfter) as? Bool ?? true
        selection.fillSuggested(from: program)
    }

    /// Picks three groups and goes to the screen named by `-screenshots`.
    private func openScreenshotScreen() {
        for key in ["Front", "Hams", "Oblique"] {
            if let group = Catalog.group(key) { toggle(group) }
        }
        switch Screenshots.screen {
        case "workout":
            startWorkout()
            session?.advance(startingRest: true)
            session?.adjustRest(by: WorkoutSession.restStep)
        case "weights":
            startWorkout()
            session?.toggleWeight("100", forKey: "Hams|Romanian Deadlift (Barbell/Dumbbell)")
            while let current = session, !current.isLastStep {
                current.advance(startingRest: false)
            }
            skipToNext()
        case "cardio":
            cardioOn = true
            startWorkout()
            while let current = session, !current.isLastStep {
                current.advance(startingRest: false)
            }
            skipToNext()
            session?.startCardio()
        case "stretch":
            startStretch(areas: ["Shoulders", "Thighs", "Core"], afterWorkout: true)
            stretch?.startHold()
        case "quicklog":
            if let preset = presets.first { logPreset(preset) }
        case "preset":
            if let preset = presets.first { presetSheet = .edit(preset) }
        case "complete":
            screen = .complete(days: 41)
        default:
            break
        }
    }

    // MARK: Home

    var canStart: Bool {
        !selection.isEmpty
    }

    /// Cardio minutes for the next workout: 0 when off, else the slider value
    /// fitted so the sets keep enough time.
    var cardioMinutesForWorkout: Int {
        cardioOn ? Cardio.clamp(cardioMinutes, forDuration: durationMinutes) : 0
    }

    func toggle(_ group: MuscleGroup) {
        guard !program.isDone(group) else { return }
        selection.toggle(group)
    }

    func startWorkout() {
        let keys = selection.orderedKeys
        guard !keys.isEmpty else { return }
        quickLog = nil
        program.markStarted(at: Date())
        save()
        session = WorkoutSession(plan: WorkoutPlan(groupKeys: keys, durationMinutes: durationMinutes,
                                                   cardioMinutes: cardioMinutesForWorkout))
        screen = .workout
        RestNotifier.requestPermission()
    }

    func resetProgram() {
        program = ProgramState()
        selection.clear()
        selection.fillSuggested(from: program)
        quickLog = nil
        save()
    }

    // MARK: Presets

    /// Adds a new preset or replaces the saved one with the same id.
    func savePreset(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        savePresets()
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }

    /// The one-tap "Log": a set for each exercise's group, then a note with Undo.
    func logPreset(_ preset: Preset) {
        let before = program
        program.recordPreset(preset, at: Date())
        save()
        let finished = preset.setsByGroup.map(\.group).filter { !before.isDone($0) && program.isDone($0) }
        quickLog = QuickLogNote(presetName: preset.name, sets: preset.totalSets,
                                finished: finished.map { "\($0.area) · \($0.name)" }, previous: before)
        selection.removeCompleted(in: program)
        selection.fillSuggested(from: program)
        if program.isComplete {
            screen = .complete(days: DayKey.daysInclusive(from: program.startDate ?? Date(), to: Date()))
        }
    }

    func undoQuickLog() {
        guard let quickLog else { return }
        program = quickLog.previous
        selection.fillSuggested(from: program)
        self.quickLog = nil
        save()
        screen = .home
    }

    func dismissQuickLog() {
        quickLog = nil
    }

    func goHome() {
        selection.clear()
        selection.fillSuggested(from: program)
        screen = .home
    }

    // MARK: Workout

    /// "Start Timer": move to the next set and start resting.
    func startRest() {
        guard let session else { return }
        if session.isLastStep {
            finishSets()
        } else {
            session.advance(startingRest: true)
        }
    }

    /// "Next Workout": move to the next set without a timer.
    func skipToNext() {
        guard let session else { return }
        if session.isLastStep {
            finishSets()
        } else {
            session.advance(startingRest: false)
        }
    }

    /// Leaves during the sets without recording anything.
    func endWorkoutEarly() {
        session?.stop()
        session = nil
        selection.removeCompleted(in: program)
        selection.fillSuggested(from: program)
        screen = .home
    }

    /// The last set is done: record it, then cardio if it's on, else the weight sheet.
    private func finishSets() {
        guard let session, !session.isFinished else { return }
        session.finish()
        let now = Date()
        program.recordWorkout(groupKeys: session.plan.groupKeys, setsPerGroup: WorkoutPlan.setsPerGroup,
                              dayKey: DayKey.string(for: now))
        program.markTrained(groupKeys: session.plan.groupKeys, at: now)
        save()
        if session.plan.cardioMinutes > 0 {
            session.showCardio()
        } else {
            isEnteringWeights = true
        }
    }

    /// "Finish Cardio" or "Skip Cardio".
    func finishCardio() {
        session?.stop()
        isEnteringWeights = true
    }

    /// "Save & Continue" on the weight sheet: weights, reps and "too heavy"
    /// ticks by weight key. Then stretching, if it's on.
    func saveWeights(_ weights: [String: String], reps: [String: [Int]], tooHeavy: Set<String>) {
        for (key, value) in weights {
            program.setWeight(value, forKey: key)
            program.logLift(forKey: key, weight: value, reps: reps[key] ?? [], tooHeavy: tooHeavy.contains(key))
        }
        save()
        isEnteringWeights = false
        let areas = session?.plan.areas ?? []
        session = nil
        selection.clear()
        selection.fillSuggested(from: program)
        if stretchAfter && !areas.isEmpty {
            startStretch(areas: areas, afterWorkout: true)
        } else {
            showHomeOrComplete()
        }
    }

    // MARK: Stretching

    func startStretch(areas: [String], afterWorkout: Bool = false) {
        let steps = Stretches.routine(areas: areas)
        guard !steps.isEmpty else { return }
        stretch = StretchSession(steps: steps, afterWorkout: afterWorkout)
        screen = .stretch
    }

    func endStretch() {
        let afterWorkout = stretch?.afterWorkout ?? false
        stretch?.stop()
        stretch = nil
        if afterWorkout {
            showHomeOrComplete()
        } else {
            screen = .home
        }
    }

    /// Catches the timers up after the app comes back from the background.
    func refreshTimers() {
        session?.refresh()
        stretch?.refresh()
    }

    private func showHomeOrComplete() {
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

    private func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: Keys.presets)
        }
    }
}
