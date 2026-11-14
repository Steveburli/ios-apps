import Foundation

/// A change someone made to a task in a shared Reminders list (one with a
/// label, such as "From my wife"): a new priority, or words added to its notes.
/// A new priority takes effect right away and waits for you to keep it, put
/// it back, or pick a different one. Notes wait for you to read them.
public struct Suggestion: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case priority, note
    }

    public var id: String
    public var taskID: String
    public var kind: Kind
    public var at: Date
    /// The list's label, such as "From my wife".
    public var from: String
    /// The words she added, for a note.
    public var text: String
    /// The task's notes before her words, so later edits fold into this one note.
    public var before: String
    /// The task's tier before her change, so "Put it back" can restore it.
    public var oldTier: Int
    /// The tier her new priority gave it.
    public var newTier: Int?

    public init(id: String = newID(), taskID: String, kind: Kind, at: Date, from: String, text: String = "",
                before: String = "", oldTier: Int, newTier: Int? = nil) {
        self.id = id
        self.taskID = taskID
        self.kind = kind
        self.at = at
        self.from = from
        self.text = text
        self.before = before
        self.oldTier = oldTier
        self.newTier = newTier
    }

    private enum CodingKeys: String, CodingKey { case id, taskID, kind, at, from, text, before, oldTier, newTier }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? newID(),
                  taskID: try c.decodeIfPresent(String.self, forKey: .taskID) ?? "",
                  kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .note,
                  at: try c.decodeIfPresent(Date.self, forKey: .at) ?? Date(),
                  from: try c.decodeIfPresent(String.self, forKey: .from) ?? "",
                  text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
                  before: try c.decodeIfPresent(String.self, forKey: .before) ?? "",
                  oldTier: try c.decodeIfPresent(Int.self, forKey: .oldTier) ?? 3,
                  newTier: try c.decodeIfPresent(Int.self, forKey: .newTier))
    }

    /// "Changed by my wife" for a list labeled "From my wife".
    public var changedBy: String {
        Suggestion.changedBy(from)
    }

    public static func changedBy(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("from "), trimmed.count > 5 {
            return "Changed by " + String(trimmed.dropFirst(5))
        }
        return trimmed.isEmpty ? "Changed in a shared list" : "Changed · \(trimmed)"
    }

    /// What was added to a reminder's notes. All of it when the old notes
    /// were rewritten, nothing when words were only taken away.
    public static func addedText(old: String, new: String) -> String {
        let old = old.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard new != old, !new.isEmpty else { return "" }
        if old.isEmpty { return new }
        if new.hasPrefix(old) { return String(new.dropFirst(old.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        if new.hasSuffix(old) { return String(new.dropLast(old.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        if old.hasPrefix(new) || old.hasSuffix(new) { return "" }
        return new
    }
}

extension PlannerState {
    /// The label of a Reminders list, if it has one.
    public func listLabel(forList listID: String) -> String? {
        guard let label = inbox.listLabels[listID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }
        return label
    }

    /// Suggestions on tasks that are still open, newest first.
    public var pendingSuggestions: [Suggestion] {
        let open = Set(activeTasks.map(\.id))
        return suggestions.filter { open.contains($0.taskID) }.sorted { $0.at > $1.at }
    }

    /// The waiting priority change on a task, for its "Changed by" tag.
    public func priorityChange(for taskID: String) -> Suggestion? {
        suggestions.first { $0.taskID == taskID && $0.kind == .priority }
    }

    /// Notes up a change made over in a shared list. Called by `syncReminders`
    /// before it copies the reminder onto the task.
    mutating func noteSharedChange(task: TaskItem, reminder: SourceTask, label: String, now: Date) {
        guard task.isActive else { return }
        if let seen = task.reminderPriority, seen != reminder.priority {
            let newTier = Tier.forReminder(priority: reminder.priority)
            if let index = suggestions.firstIndex(where: { $0.taskID == task.id && $0.kind == .priority }) {
                if newTier == suggestions[index].oldTier {
                    // Changed back before you answered.
                    suggestions.remove(at: index)
                } else {
                    suggestions[index].newTier = newTier
                    suggestions[index].at = now
                }
            } else if newTier != task.tier {
                suggestions.append(Suggestion(taskID: task.id, kind: .priority, at: now, from: label,
                                              oldTier: task.tier, newTier: newTier))
            }
            updateTask(task.id) { $0.tier = newTier }
        }
        guard reminder.notes != task.notes else { return }
        if let index = suggestions.firstIndex(where: { $0.taskID == task.id && $0.kind == .note }) {
            // One note per task until you answer: everything added since the notes you last saw.
            let added = Suggestion.addedText(old: suggestions[index].before, new: reminder.notes)
            if added.isEmpty {
                suggestions.remove(at: index)
            } else {
                suggestions[index].text = added
                suggestions[index].at = now
            }
        } else {
            let added = Suggestion.addedText(old: task.notes, new: reminder.notes)
            if !added.isEmpty {
                suggestions.append(Suggestion(taskID: task.id, kind: .note, at: now, from: label,
                                              text: added, before: task.notes, oldTier: task.tier))
            }
        }
    }

    /// Keep her change (or, for a note, "Got it").
    public mutating func approveSuggestion(_ id: String) {
        suggestions.removeAll { $0.id == id }
    }

    /// Put the priority back where it was. A note is just set aside.
    public mutating func denySuggestion(_ id: String) {
        guard let suggestion = suggestions.first(where: { $0.id == id }) else { return }
        if suggestion.kind == .priority {
            updateTask(suggestion.taskID) { $0.tier = suggestion.oldTier }
        }
        suggestions.removeAll { $0.id == id }
    }

    /// Pick the priority yourself. That answers any waiting priority change on the task too.
    public mutating func adjustSuggestion(_ id: String, tier: Int) {
        guard let suggestion = suggestions.first(where: { $0.id == id }) else { return }
        updateTask(suggestion.taskID) { $0.tier = tier }
        suggestions.removeAll { $0.id == id || ($0.taskID == suggestion.taskID && $0.kind == .priority) }
    }

    /// Drops suggestions on tasks that are finished, let go, or gone.
    mutating func pruneSuggestions() {
        let open = Set(activeTasks.map(\.id))
        suggestions.removeAll { !open.contains($0.taskID) }
    }
}
