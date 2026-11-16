import XCTest
@testable import DoThisNowKit

/// Changes made in a shared Reminders list, such as one labeled "From my wife".
final class SuggestionTests: XCTestCase {
    private func reminder(_ id: String, priority: Int = 0, notes: String = "", list: String = "house") -> SourceTask {
        SourceTask(ref: SourceRef(.reminders, id), title: id, notes: notes, listID: list, listName: list, priority: priority)
    }

    private func sharedState() -> PlannerState {
        var state = PlannerState()
        state.inbox.reminders.on = true
        state.inbox.listLabels = ["house": "From my wife"]
        return state
    }

    private func sync(_ open: [SourceTask], _ state: inout PlannerState, at now: Date = wednesday10am) {
        state.syncReminders(open, now: now, calendar: utc)
    }

    func testNewTasksAndOldFilesMakeNoSuggestions() {
        var state = sharedState()
        sync([reminder("Porch light", priority: 3, notes: "Bulb is in the garage")], &state)
        XCTAssertEqual(state.tasks[0].tier, 1)
        XCTAssertEqual(state.tasks[0].reminderPriority, 3)
        XCTAssertTrue(state.suggestions.isEmpty)

        // A task saved before this field existed just learns the priority.
        state.updateTask(state.tasks[0].id) { $0.reminderPriority = nil }
        sync([reminder("Porch light", priority: 1, notes: "Bulb is in the garage")], &state)
        XCTAssertTrue(state.suggestions.isEmpty)
        XCTAssertEqual(state.tasks[0].reminderPriority, 1)
    }

    func testHerPriorityChangeTakesEffectAndWaitsForYou() {
        var state = sharedState()
        sync([reminder("Gutters")], &state)
        let id = state.tasks[0].id
        XCTAssertEqual(state.tasks[0].tier, 3)

        sync([reminder("Gutters", priority: 3)], &state)
        XCTAssertEqual(state.tasks[0].tier, 1, "Her change shows right away")
        XCTAssertEqual(state.pendingSuggestions.count, 1)
        let suggestion = state.pendingSuggestions[0]
        XCTAssertEqual(suggestion.kind, .priority)
        XCTAssertEqual(suggestion.oldTier, 3)
        XCTAssertEqual(suggestion.newTier, 1)
        XCTAssertEqual(state.priorityChange(for: id)?.changedBy, "Changed by my wife")

        // Syncing again with nothing new adds nothing.
        sync([reminder("Gutters", priority: 3)], &state)
        XCTAssertEqual(state.suggestions.count, 1)

        state.denySuggestion(suggestion.id)
        XCTAssertEqual(state.tasks[0].tier, 3, "Put it back")
        XCTAssertNil(state.priorityChange(for: id))

        sync([reminder("Gutters", priority: 3)], &state)
        XCTAssertEqual(state.tasks[0].tier, 3, "A turned-down change doesn't come back until she changes it again")
        XCTAssertTrue(state.suggestions.isEmpty)
    }

    func testKeepAdjustAndChangingItBack() {
        var state = sharedState()
        sync([reminder("Paint")], &state)

        sync([reminder("Paint", priority: 2)], &state)
        state.approveSuggestion(state.suggestions[0].id)
        XCTAssertEqual(state.tasks[0].tier, 2)
        XCTAssertTrue(state.suggestions.isEmpty)

        sync([reminder("Paint", priority: 3)], &state)
        XCTAssertEqual(state.suggestions[0].oldTier, 2)
        state.adjustSuggestion(state.suggestions[0].id, tier: 4)
        XCTAssertEqual(state.tasks[0].tier, 4)
        XCTAssertTrue(state.suggestions.isEmpty)

        sync([reminder("Paint", priority: 2)], &state)
        XCTAssertEqual(state.suggestions.count, 1)
        sync([reminder("Paint", priority: 0)], &state)
        XCTAssertEqual(state.suggestions[0].newTier, 3, "A second change updates the same suggestion")
        XCTAssertEqual(state.suggestions[0].oldTier, 4)
        state.approveSuggestion(state.suggestions[0].id)

        sync([reminder("Paint", priority: 3)], &state)
        XCTAssertEqual(state.suggestions.count, 1)
        sync([reminder("Paint", priority: 0)], &state)
        XCTAssertTrue(state.suggestions.isEmpty, "Changed back before you answered: nothing left to answer")
        XCTAssertEqual(state.tasks[0].tier, 3)
    }

    func testHerNotesBecomeSuggestions() {
        var state = sharedState()
        sync([reminder("Porch light", notes: "Bulb is in the garage")], &state)

        sync([reminder("Porch light", notes: "Bulb is in the garage\nPlease before Saturday")], &state)
        XCTAssertEqual(state.pendingSuggestions.map(\.text), ["Please before Saturday"])
        XCTAssertEqual(state.pendingSuggestions[0].kind, .note)
        XCTAssertEqual(state.tasks[0].notes, "Bulb is in the garage\nPlease before Saturday")
        XCTAssertEqual(state.tasks[0].tier, 3, "Words alone don't change the priority")

        sync([reminder("Porch light", notes: "Bulb is in the garage\nPlease before Saturday!!")], &state)
        XCTAssertEqual(state.pendingSuggestions.map(\.text), ["Please before Saturday!!"], "Still the same note")

        sync([reminder("Porch light", notes: "Please before Saturday!!")], &state)
        XCTAssertEqual(state.suggestions.count, 1, "Still one note per task")

        state.adjustSuggestion(state.suggestions[0].id, tier: 1)
        XCTAssertEqual(state.tasks[0].tier, 1)
        XCTAssertTrue(state.suggestions.isEmpty)
    }

    func testYourOwnListsMakeNoSuggestions() {
        var state = sharedState()
        sync([reminder("Call", list: "work")], &state)
        sync([reminder("Call", priority: 3, notes: "new", list: "work")], &state)
        XCTAssertEqual(state.tasks[0].tier, 3, "Your own reminders keep the priority you set here")
        XCTAssertTrue(state.suggestions.isEmpty)
    }

    func testHerAddingAndRemovingTasksShowsUpHere() {
        var state = sharedState()
        sync([reminder("Porch light")], &state)
        sync([reminder("Porch light"), reminder("Gutters")], &state)
        XCTAssertEqual(state.activeTasks.map(\.title), ["Porch light", "Gutters"])

        sync([reminder("Gutters", priority: 3)], &state)
        XCTAssertEqual(state.activeTasks.map(\.title), ["Gutters"], "Removed from her list, gone from yours")
        XCTAssertEqual(state.suggestions.count, 1)

        sync([], &state)
        XCTAssertTrue(state.suggestions.isEmpty, "Suggestions on finished tasks go away")
    }

    func testAddedTextAndLabels() {
        XCTAssertEqual(Suggestion.addedText(old: "", new: "Hi"), "Hi")
        XCTAssertEqual(Suggestion.addedText(old: "a", new: "a b"), "b")
        XCTAssertEqual(Suggestion.addedText(old: "a", new: "b\na"), "b")
        XCTAssertEqual(Suggestion.addedText(old: "a b", new: "a"), "")
        XCTAssertEqual(Suggestion.addedText(old: "a", new: "c"), "c")
        XCTAssertEqual(Suggestion.changedBy("Jen"), "Changed · Jen")
    }

    func testSuggestionsSave() throws {
        var state = sharedState()
        sync([reminder("Gutters")], &state)
        sync([reminder("Gutters", priority: 3, notes: "Soon please")], &state)
        XCTAssertEqual(state.suggestions.count, 2)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(PlannerState.self, from: data), state)
    }
}
