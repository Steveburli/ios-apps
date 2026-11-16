import SwiftUI
import DoThisNowKit

/// The break bank: focused work earns break time to spend.
extension AppModel {
    func startFocus() {
        state.startFocus(at: Date(), calendar: calendar)
        Notifier.requestPermission()
        commit()
    }

    func stopFocus() {
        let earned = state.stopFocus(at: Date(), calendar: calendar)
        commit()
        if let earned { show("Focus saved. +\(BreakText.amount(earned)) of break") }
    }

    func confirmStillWorking() {
        state.confirmStillWorking(at: Date())
        commit()
    }

    func startBreak(minutes: Int) {
        state.startBreak(minutes: minutes, at: Date(), calendar: calendar)
        Notifier.requestPermission()
        commit()
    }

    /// "Back to work": ends the break early and keeps what's left.
    func endBreak() {
        state.endBreak(at: Date(), calendar: calendar)
        commit()
        let left = state.breakBalance(at: Date(), calendar: calendar)
        show(left >= 60 ? "Break over. \(BreakText.amount(left)) still in the bank" : "Break over")
    }

    /// "Fill my break": starts a break for everything earned and asks the
    /// Now tab for tasks that fit it.
    func fillBreak() {
        let minutes = state.breakMinutesAvailable(at: Date(), calendar: calendar)
        guard minutes >= 1 else { return }
        state.startBreak(minutes: minutes, at: Date(), calendar: calendar)
        state.context.timeMinutes = minutes
        Notifier.requestPermission()
        commit()
        tab = .now
        go()
    }

    func saveBreakIdeas(_ ideas: [BreakIdea]) {
        state.breaks.ideas = ideas
            .map { idea in
                var idea = idea
                idea.name = idea.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return idea
            }
            .filter { !$0.name.isEmpty }
        commit()
    }

    /// Banks break time for a Now-tab session that's ending. Call before
    /// `state.endSession`, while the session is still there.
    func earnBreakForSession(at now: Date) {
        guard let session = state.active else { return }
        state.earnBreak(forWork: session.elapsed(at: now), at: now, calendar: calendar)
    }

    /// Called every second: ends a break when its time is up.
    func checkBreak(_ date: Date) {
        guard let current = state.breaks.current, date >= current.endsAt else { return }
        state.endBreak(at: date, calendar: calendar)
        if state.settings.sound { Sounds.chime() }
        commit()
        show("Break’s over")
    }
}

enum BreakText {
    /// "18 min", "1h 5m", or "under a minute".
    static func amount(_ seconds: Double) -> String {
        let minutes = abs(seconds) / 60
        if minutes < 1 { return "under a minute" }
        let whole = Int(minutes.rounded(.down))
        return whole < 60 ? "\(whole) min" : TimeText.duration(whole)
    }

    /// "Break earned: 18 min" or "You owe 6 min of break".
    static func balance(_ seconds: Double) -> String {
        if seconds <= -60 { return "You owe \(amount(seconds)) of break" }
        if seconds < 60 { return "No break earned yet" }
        return "Break earned: \(amount(seconds))"
    }
}
