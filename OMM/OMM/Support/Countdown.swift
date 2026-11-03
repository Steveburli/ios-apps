import Foundation
import Observation

/// A countdown for rest, cardio or a stretch hold. It stores an end date and
/// never counts ticks, so it stays right after the app is backgrounded. A
/// local notification covers the locked phone; in the foreground the chime
/// plays instead.
@Observable
@MainActor
final class Countdown {
    enum State: Equatable {
        case idle
        case running(endsAt: Date, total: Int)
        case done
    }

    private(set) var state: State = .idle
    /// Goes up each time the countdown runs out while the app is open. Drives the haptic.
    private(set) var endedCount = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var alert = (title: "", body: "")

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func secondsLeft(now: Date) -> Int? {
        guard case .running(let endsAt, _) = state else { return nil }
        return Int(max(0, endsAt.timeIntervalSince(now)).rounded(.up))
    }

    /// How far through the countdown is, 0 to 1.
    func fraction(now: Date) -> Double {
        switch state {
        case .idle: return 0
        case .done: return 1
        case .running(let endsAt, let total):
            guard total > 0 else { return 1 }
            return 1 - max(0, endsAt.timeIntervalSince(now)) / Double(total)
        }
    }

    func start(seconds: Int, title: String, body: String) {
        cancel()
        alert = (title, body)
        guard seconds > 0 else {
            state = .done
            return
        }
        run(until: Date().addingTimeInterval(TimeInterval(seconds)), total: seconds)
    }

    /// Moves the end of a running countdown by `delta` seconds.
    func adjust(by delta: Int, now: Date = Date()) {
        guard case .running(let endsAt, let total) = state else { return }
        let newEnd = endsAt.addingTimeInterval(TimeInterval(delta))
        task?.cancel()
        RestNotifier.cancel()
        if newEnd <= now {
            state = .done
            Chime.play()
            endedCount += 1
        } else {
            run(until: newEnd, total: max(1, total + delta))
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        RestNotifier.cancel()
        state = .idle
    }

    /// Catches up after the app comes back from the background.
    func refresh(now: Date = Date()) {
        if case .running(let endsAt, _) = state, now >= endsAt {
            task?.cancel()
            state = .done
        }
    }

    private func run(until endsAt: Date, total: Int) {
        state = .running(endsAt: endsAt, total: total)
        let seconds = endsAt.timeIntervalSinceNow
        RestNotifier.schedule(after: seconds, title: alert.title, body: alert.body)
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.ended(endsAt: endsAt)
        }
    }

    private func ended(endsAt: Date) {
        guard case .running(let current, _) = state, current == endsAt else { return }
        state = .done
        RestNotifier.cancel()
        // Stay quiet if it ran out long ago while the app was suspended.
        if Date().timeIntervalSince(endsAt) < 3 {
            Chime.play()
            endedCount += 1
        }
    }
}

enum Clock {
    /// "2:30"
    static func string(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
