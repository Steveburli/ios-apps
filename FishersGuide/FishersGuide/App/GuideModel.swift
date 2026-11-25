import Foundation
import GuideKit
import Observation

/// Owns the tour, the trigger engine, the narrator and the location source, and decides
/// what to say as fixes come in from the GPS or the demo drive.
@MainActor
@Observable
final class GuideModel {
    enum Source: String { case gps, demo }

    struct Heard: Codable, Identifiable, Hashable {
        var id = UUID()
        var stopID: String
        var date: Date
        /// Picked while another story was playing, and passed before it could start.
        var missed = false
    }

    struct Settings: Codable, Equatable {
        var trigger = TriggerSettings()
        var rate: Float = 0.5
        var voiceID: String?
        /// Demo drive speed, meters per second (22 ≈ 50 mph).
        var demoSpeed: Double = 22
    }

    let tour: Tour
    let narrator = Narrator()
    let location = LocationService()

    private(set) var engine: TriggerEngine
    private(set) var isTouring = false
    private(set) var source: Source = .gps
    private(set) var lastFix: Fix?
    /// An arrival picked while something else was playing. It plays next if still near.
    private(set) var upNext: Trigger?
    private(set) var history: [Heard]
    var settings: Settings {
        didSet { applySettings() }
    }
    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) }
    }
    /// The stop whose detail sheet is open.
    var selectedStopID: String?

    @ObservationIgnored private var demoTask: Task<Void, Never>?
    private(set) var demoElapsed: TimeInterval = 0
    @ObservationIgnored private var demoStart = Date()
    @ObservationIgnored private let defaults: UserDefaults

    enum Keys {
        static let played = "guide.played.v1"
        static let history = "guide.history.v1"
        static let settings = "guide.settings.v1"
        static let onboarded = "guide.onboarded.v1"
    }

    init(tour: Tour? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // The bundled JSON is checked by the package tests, so this only fails on a broken build.
        self.tour = tour ?? ((try? Tour.bundledFishers()) ?? Tour(
            id: "empty", title: "Fishers Guide", summary: "", center: GeoPoint(lat: 39.956, lon: -86.013),
            span: 0.2, stops: [], demoRoute: []))
        let settings = GuideModel.load(Settings.self, key: Keys.settings, from: defaults) ?? Settings()
        let played = GuideModel.load([String: Date].self, key: Keys.played, from: defaults) ?? [:]
        self.settings = settings
        self.engine = TriggerEngine(settings: settings.trigger, played: played)
        self.history = GuideModel.load([Heard].self, key: Keys.history, from: defaults) ?? []
        self.hasOnboarded = defaults.bool(forKey: Keys.onboarded)

        narrator.rate = settings.rate
        narrator.voiceIdentifier = settings.voiceID
        narrator.onFinish = { [weak self] _ in
            guard let self, let fix = self.lastFix, self.isTouring else { return }
            self.handle(fix)
        }
        narrator.onSkipRequest = { [weak self] in self?.skip() }
        location.onFix = { [weak self] fix in
            guard let self, self.isTouring, self.source == .gps else { return }
            self.handle(fix)
        }
    }

    // MARK: - Tour control

    func startTour(source: Source) {
        stopTour()
        self.source = source
        isTouring = true
        switch source {
        case .gps:
            location.start()
        case .demo:
            startDemo()
        }
    }

    func stopTour() {
        isTouring = false
        demoTask?.cancel()
        demoTask = nil
        location.stop()
        narrator.stop()
        upNext = nil
        if source == .demo { lastFix = nil }
    }

    // MARK: - Deciding what to say

    func handle(_ fix: Fix) {
        lastFix = fix
        if narrator.isBusy {
            // Hold on to the next arrival so it isn't lost while a story is playing.
            guard upNext == nil,
                  let next = engine.candidates(stops: tour.stops, fix: fix).first(where: { $0.kind == .arrival })
            else { return }
            engine.markPlayed(next.stop.id, at: fix.time)
            upNext = next
            return
        }

        if let waiting = upNext {
            upNext = nil
            if engine.isStillRelevant(waiting, fix: fix) {
                speak(refreshed(waiting, from: fix), at: fix.time)
                return
            }
            history.insert(Heard(stopID: waiting.stop.id, date: fix.time, missed: true), at: 0)
            engine.forget(waiting.stop.id)
            save()
        }

        if let trigger = engine.next(stops: tour.stops, fix: fix) {
            speak(trigger, at: fix.time)
        }
    }

    /// Rebuilds a held trigger's intro ("on your left") for where you are now.
    private func refreshed(_ trigger: Trigger, from fix: Fix) -> Trigger {
        var copy = trigger
        let course = fix.speed >= settings.trigger.minCourseSpeed ? fix.course : nil
        let bearing = Geo.bearing(from: fix.point, to: trigger.stop.location)
        copy.side = course.map { RelativeSide(course: $0, bearingToTarget: bearing) }
        copy.distance = Geo.distance(fix.point, trigger.stop.location)
        copy.script = Script.arrival(trigger.stop, side: copy.side, distance: copy.distance, course: course)
        return copy
    }

    private func speak(_ trigger: Trigger, at time: Date) {
        narrator.play(Narrator.Narration(stopID: trigger.stop.id, title: trigger.stop.title,
                                         script: trigger.script,
                                         audioFile: trigger.kind == .arrival ? trigger.stop.audioFile : nil,
                                         isTeaser: trigger.kind == .headsUp))
        if trigger.kind == .arrival {
            history.removeAll { $0.stopID == trigger.stop.id && $0.missed }
            history.insert(Heard(stopID: trigger.stop.id, date: time), at: 0)
            save()
        }
    }

    // MARK: - By hand

    /// Plays a stop's story now, from the list or the detail screen.
    func playStory(_ stop: Stop) {
        let course = lastFix.flatMap { $0.speed >= settings.trigger.minCourseSpeed ? $0.course : nil }
        narrator.play(Narrator.Narration(stopID: stop.id, title: stop.title,
                                         script: stop.narration(forCourse: course),
                                         audioFile: stop.audioFile, isTeaser: false))
        let now = lastFix?.time ?? Date()
        engine.markPlayed(stop.id, at: now)
        history.removeAll { $0.stopID == stop.id && $0.missed }
        history.insert(Heard(stopID: stop.id, date: now), at: 0)
        save()
    }

    /// Ends the current story; the next one can start right away.
    func skip() {
        narrator.stop()
        if isTouring, let fix = lastFix { handle(fix) }
    }

    func resetHistory() {
        engine.resetHistory()
        history = []
        upNext = nil
        save()
    }

    func hasHeard(_ stopID: String) -> Bool {
        history.contains { $0.stopID == stopID && !$0.missed }
    }

    var heardCount: Int {
        Set(history.filter { !$0.missed }.map(\.stopID)).count
    }

    var pointsOfInterest: [Stop] {
        tour.stops.filter { $0.kind == .poi }
    }

    func distance(to stop: Stop) -> Double? {
        lastFix.map { Geo.distance($0.point, stop.location) }
    }

    // MARK: - Demo drive

    private var simulator: RouteSimulator {
        RouteSimulator(waypoints: tour.demoRoute, speed: settings.demoSpeed)
    }

    private func startDemo() {
        demoStart = Date()
        demoElapsed = 0
        demoTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let fix = self.simulator.fix(at: self.demoElapsed, start: self.demoStart) else {
                    // The drive is over; let the last story finish.
                    self.isTouring = false
                    return
                }
                self.handle(fix)
                self.demoElapsed += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Jumps the demo car to just before the next stop it hasn't told you about yet.
    func skipDemoAhead() {
        guard isTouring, source == .demo else { return }
        narrator.stop()
        upNext = nil
        let sim = simulator
        var probe = engine
        probe.settings.headsUps = false
        var t = demoElapsed + 5
        while let fix = sim.fix(at: t, start: demoStart) {
            if probe.candidates(stops: tour.stops, fix: fix).contains(where: { $0.stop.kind == .poi }) {
                demoElapsed = max(demoElapsed, t - 4)
                return
            }
            t += 2
        }
    }

    var demoRouteProgress: Double {
        let duration = simulator.duration
        return duration > 0 ? min(1, demoElapsed / duration) : 0
    }

    // MARK: - Saving

    private func applySettings() {
        engine.settings = settings.trigger
        narrator.rate = settings.rate
        narrator.voiceIdentifier = settings.voiceID
        GuideModel.store(settings, key: Keys.settings, in: defaults)
    }

    private func save() {
        GuideModel.store(engine.played, key: Keys.played, in: defaults)
        GuideModel.store(Array(history.prefix(200)), key: Keys.history, in: defaults)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func store<T: Encodable>(_ value: T, key: String, in defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    // MARK: - Screenshots

    /// Puts the model in a picture-ready state without playing sound or using the GPS.
    func stageForScreenshots(at fix: Fix, heard: [String], nowPlaying stopID: String?) {
        lastFix = fix
        isTouring = true
        source = .demo
        for (i, id) in heard.enumerated() {
            history.append(Heard(stopID: id, date: fix.time.addingTimeInterval(Double(-600 * (i + 1)))))
            engine.markPlayed(id, at: fix.time)
        }
        if let stopID, let stop = tour.stop(id: stopID) {
            let bearing = Geo.bearing(from: fix.point, to: stop.location)
            let side = fix.course.map { RelativeSide(course: $0, bearingToTarget: bearing) }
            narrator.showForScreenshot(Narrator.Narration(
                stopID: stop.id, title: stop.title,
                script: Script.arrival(stop, side: side, distance: Geo.distance(fix.point, stop.location), course: fix.course),
                audioFile: nil, isTeaser: false))
        }
    }
}
