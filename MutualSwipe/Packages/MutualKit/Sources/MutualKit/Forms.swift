import Foundation

// A deck's questions: a short form people fill in before they swipe, like
// flight times for a trip. The deck's owner writes the questions (or starts
// from a ready-made set), anyone can fill in answers for anyone, and each
// person confirms their own. Everyone in the group sees all the answers.
// Answers to an "Your ideas" question become new cards, with a Love from
// the person who suggested them.

/// What kind of answer a question takes.
public enum QuestionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case choice
    case yesNo = "yesno"
    case date
    /// One idea per line. Each becomes a card in the deck.
    case ideas

    public var id: Self { self }

    public var label: String {
        switch self {
        case .text: return "Text"
        case .choice: return "Pick one"
        case .yesNo: return "Yes or no"
        case .date: return "Date"
        case .ideas: return "Your ideas"
        }
    }

    public var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .choice: return "list.bullet"
        case .yesNo: return "checkmark.circle"
        case .date: return "calendar"
        case .ideas: return "lightbulb"
        }
    }
}

public struct FormQuestion: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: QuestionKind
    public var prompt: String
    /// The choices, for a "Pick one" question.
    public var options: [String]
    /// A short example shown in an empty answer.
    public var hint: String

    public init(id: String = makeID(), kind: QuestionKind, prompt: String, options: [String] = [], hint: String = "") {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.options = options
        self.hint = hint
    }

    /// Trims the text and drops empty or repeated choices. Nil when there's no question.
    public func cleaned() -> FormQuestion? {
        let prompt = self.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        var copy = self
        copy.prompt = String(prompt.prefix(200))
        copy.hint = String(hint.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        var seen = Set<String>()
        copy.options = kind == .choice ? options.compactMap { raw in
            let option = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            guard !option.isEmpty, seen.insert(option.lowercased()).inserted else { return nil }
            return option
        } : []
        return copy
    }

    /// Saved in the deck record as a small JSON string.
    public var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func decode(_ text: String) -> FormQuestion? {
        try? JSONDecoder().decode(FormQuestion.self, from: Data(text.utf8))
    }
}

/// One person's answers to one deck's questions.
public struct FormAnswers: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var groupID: String
    public var deckID: String
    /// Whose answers these are.
    public var playerID: String
    /// Question ID → answer. Yes/no is "yes" or "no", a date is "yyyy-MM-dd",
    /// and ideas are one per line.
    public var values: [String: String]
    /// Who saved them last: the person themself, or someone filling in for them.
    public var filledBy: String
    /// When the person themself last confirmed them. Nil after someone else edits.
    public var confirmedAt: Date?
    public var updatedAt: Date
    /// Ideas already turned into cards, lowercased, so a deleted card isn't made again.
    public var ideasMade: [String]
    public var systemFields: Data?

    public init(groupID: String, deckID: String, playerID: String, values: [String: String] = [:],
                filledBy: String, confirmedAt: Date? = nil, updatedAt: Date, ideasMade: [String] = []) {
        self.id = FormAnswers.id(deckID: deckID, playerID: playerID)
        self.groupID = groupID
        self.deckID = deckID
        self.playerID = playerID
        self.values = values
        self.filledBy = filledBy
        self.confirmedAt = confirmedAt
        self.updatedAt = updatedAt
        self.ideasMade = ideasMade
    }

    public static func id(deckID: String, playerID: String) -> String {
        "answer_\(deckID)_\(playerID)"
    }

    /// The person looked them over and confirmed them, and no one changed them since.
    public var isConfirmed: Bool {
        confirmedAt != nil && filledBy == playerID
    }

    /// Someone else filled these in and the person hasn't confirmed them yet.
    public var waitingOnConfirm: Bool {
        !isConfirmed && filledBy != playerID && !values.isEmpty
    }

    public func value(_ question: FormQuestion) -> String {
        values[question.id] ?? ""
    }

    /// How many of the questions have an answer.
    public func answered(_ questions: [FormQuestion]) -> Int {
        questions.filter { !value($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
}

public enum Forms {
    /// Whether a person still has to fill in or confirm a deck's questions.
    public static func needsAnswers(questions: [FormQuestion], answers: FormAnswers?) -> Bool {
        !questions.isEmpty && !(answers?.isConfirmed ?? false)
    }

    /// An answer as people read it.
    public static func display(_ value: String, for question: FormQuestion) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        switch question.kind {
        case .yesNo:
            return trimmed == "yes" ? "Yes" : trimmed == "no" ? "No" : trimmed
        case .date:
            guard let date = day(from: trimmed) else { return trimmed }
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        case .ideas:
            return ideas(in: trimmed).joined(separator: "\n")
        case .text, .choice:
            return trimmed
        }
    }

    // MARK: Dates

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// A date answer, as saved.
    public static func dayString(_ date: Date) -> String {
        dayFormatter().string(from: date)
    }

    public static func day(from text: String) -> Date? {
        dayFormatter().date(from: text)
    }

    // MARK: Ideas

    /// The ideas in an answer: one per line, with list bullets and numbers
    /// taken off, empties and repeats dropped.
    public static func ideas(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var idea = line.trimmingCharacters(in: .whitespaces)
            while let first = idea.first, "-•*·–".contains(first) {
                idea = String(idea.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if let match = idea.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) {
                idea = String(idea[match.upperBound...])
            }
            idea = String(idea.trimmingCharacters(in: .whitespaces).prefix(80))
            guard !idea.isEmpty, seen.insert(idea.lowercased()).inserted else { continue }
            result.append(idea)
        }
        return result
    }

    /// What to do with a person's ideas when they confirm their answers.
    public struct IdeaPlan: Equatable, Sendable {
        /// Ideas that need a new card.
        public var newCards: [String]
        /// Existing cards (by ID) that match an idea, which get a Love from the person.
        public var matchingCards: [String]
        /// Every idea handled, lowercased, to remember so it's not made twice.
        public var made: [String]
    }

    /// Ideas from every ideas question, minus the ones already handled before.
    /// An idea with the same title as a card already in the deck doesn't make
    /// a new card; the person's Love goes on that card instead.
    public static func ideaPlan(questions: [FormQuestion], values: [String: String], alreadyMade: [String],
                                cards: [Card]) -> IdeaPlan {
        let done = Set(alreadyMade.map { $0.lowercased() })
        var seen = Set<String>()
        var plan = IdeaPlan(newCards: [], matchingCards: [], made: alreadyMade)
        for question in questions where question.kind == .ideas {
            for idea in ideas(in: values[question.id] ?? "") {
                let key = idea.lowercased()
                guard !done.contains(key), seen.insert(key).inserted else { continue }
                plan.made.append(key)
                if let card = cards.first(where: { $0.title.lowercased() == key }) {
                    plan.matchingCards.append(card.id)
                } else {
                    plan.newCards.append(idea)
                }
            }
        }
        return plan
    }

    /// The subtitle on a card made from someone's idea.
    public static func ideaSubtitle(by name: String) -> String {
        name.isEmpty ? "Someone’s idea" : "\(name)’s idea"
    }
}

/// Ready-made question sets to start from and edit.
public struct FormTemplate: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let blurb: String
    public let symbol: String
    public let questions: [FormQuestion]

    /// Fresh copies with new IDs, so two decks never share question IDs.
    public func makeQuestions() -> [FormQuestion] {
        questions.map { question in
            var copy = question
            copy.id = makeID()
            return copy
        }
    }

    public static let all: [FormTemplate] = [trip, dinner, nightOut]

    public static let trip = FormTemplate(
        id: "trip", title: "Trip", blurb: "Flights, where you’re staying, work days and the vibe you want.",
        symbol: "airplane", questions: [
            FormQuestion(kind: .date, prompt: "When do you get in?"),
            FormQuestion(kind: .text, prompt: "Your flight in", hint: "Airline, flight number, landing time"),
            FormQuestion(kind: .date, prompt: "When do you leave?"),
            FormQuestion(kind: .text, prompt: "Your flight out", hint: "Airline, flight number, takeoff time"),
            FormQuestion(kind: .text, prompt: "Where are you staying?", hint: "Hotel, with friends, not sure yet"),
            FormQuestion(kind: .yesNo, prompt: "Are you working during the trip?"),
            FormQuestion(kind: .text, prompt: "If so, which days and when are you busy?",
                         hint: "Tue and Wed 9–5, from home, can step out for lunch"),
            FormQuestion(kind: .choice, prompt: "What pace do you want?",
                         options: ["Lots of chill time", "A good mix", "Packed with things to do"]),
            FormQuestion(kind: .choice, prompt: "What are you most excited for?",
                         options: ["Food and drinks", "Outdoors", "Culture and sights", "Nightlife", "Just hanging out"]),
            FormQuestion(kind: .text, prompt: "Anything we should know?", hint: "Food allergies, a budget, an early night"),
            FormQuestion(kind: .ideas, prompt: "Any ideas or recommendations?",
                         hint: "One per line, like a restaurant or a hike"),
        ])

    public static let dinner = FormTemplate(
        id: "dinner", title: "Dinner out", blurb: "Timing, budget, food rules and places to try.",
        symbol: "fork.knife", questions: [
            FormQuestion(kind: .text, prompt: "Which nights work for you?", hint: "Friday after 7, not Sunday"),
            FormQuestion(kind: .choice, prompt: "Budget per person?", options: ["$", "$$", "$$$", "Splurge"]),
            FormQuestion(kind: .text, prompt: "Anything you can’t or won’t eat?", hint: "Vegetarian, no shellfish"),
            FormQuestion(kind: .choice, prompt: "What kind of night?",
                         options: ["Quick and casual", "Sit-down and chatty", "Something special"]),
            FormQuestion(kind: .ideas, prompt: "Places you’d like to try?", hint: "One per line"),
        ])

    public static let nightOut = FormTemplate(
        id: "night", title: "Night out", blurb: "When you’re free, how late you’ll stay out and your picks.",
        symbol: "moon.stars", questions: [
            FormQuestion(kind: .date, prompt: "Best night for you?"),
            FormQuestion(kind: .choice, prompt: "How late are you staying out?",
                         options: ["Home by 10", "Around midnight", "Until they close"]),
            FormQuestion(kind: .yesNo, prompt: "Do you need a ride?"),
            FormQuestion(kind: .choice, prompt: "What’s the vibe?",
                         options: ["Low-key drinks", "Live music", "Dancing", "Games or an activity"]),
            FormQuestion(kind: .ideas, prompt: "Spots or things to do?", hint: "One per line"),
        ])
}
