import Foundation
import DoThisNowKit

/// Answers to changes made in a shared Reminders list (see `Suggestion`).
extension AppModel {
    func approveSuggestion(_ id: String) {
        state.approveSuggestion(id)
        commit()
    }

    func denySuggestion(_ id: String) {
        state.denySuggestion(id)
        if nowStep == .pick { refreshPicks() }
        commit()
    }

    func adjustSuggestion(_ id: String, tier: Int) {
        state.adjustSuggestion(id, tier: tier)
        if nowStep == .pick { refreshPicks() }
        commit()
    }
}
