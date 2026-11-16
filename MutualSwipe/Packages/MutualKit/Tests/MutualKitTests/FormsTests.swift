import XCTest
@testable import MutualKit

final class FormsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func card(_ title: String, id: String) -> Card {
        Card(id: id, groupID: "g", deckID: "d", draft: CardDraft(title: title), order: 0, createdAt: now)
    }

    func testIdeasAreSplitAndCleaned() {
        let text = """
        - Rooftop dinner
        • Canal kayaks
        2. Food truck night

        rooftop dinner
        1) Indy 500 museum
        """
        XCTAssertEqual(Forms.ideas(in: text), ["Rooftop dinner", "Canal kayaks", "Food truck night", "Indy 500 museum"])
        XCTAssertEqual(Forms.ideas(in: "  \n \n"), [])
    }

    func testIdeaPlanMakesNewCardsAndMatchesExistingOnes() {
        let ideas = FormQuestion(id: "i", kind: .ideas, prompt: "Ideas?")
        let text = FormQuestion(id: "t", kind: .text, prompt: "Notes")
        let plan = Forms.ideaPlan(questions: [text, ideas],
                                  values: ["i": "Canal kayaks\nRooftop dinner\nZoo", "t": "Not an idea"],
                                  alreadyMade: ["zoo"], cards: [card("Rooftop Dinner", id: "c1")])
        XCTAssertEqual(plan.newCards, ["Canal kayaks"])
        XCTAssertEqual(plan.matchingCards, ["c1"])
        XCTAssertEqual(plan.made, ["zoo", "canal kayaks", "rooftop dinner"])

        // Confirming again with the same ideas makes nothing new.
        let again = Forms.ideaPlan(questions: [ideas], values: ["i": "Canal kayaks\nRooftop dinner"],
                                   alreadyMade: plan.made, cards: [card("Rooftop Dinner", id: "c1")])
        XCTAssertEqual(again.newCards, [])
        XCTAssertEqual(again.matchingCards, [])
    }

    func testConfirmingAndFillingInForSomeoneElse() {
        var answers = FormAnswers(groupID: "g", deckID: "d", playerID: "sam", values: ["q": "x"],
                                  filledBy: "alex", updatedAt: now)
        let questions = [FormQuestion(id: "q", kind: .text, prompt: "Flight?")]
        XCTAssertEqual(answers.id, "answer_d_sam")
        XCTAssertTrue(answers.waitingOnConfirm)
        XCTAssertFalse(answers.isConfirmed)
        XCTAssertTrue(Forms.needsAnswers(questions: questions, answers: answers))

        answers.filledBy = "sam"
        answers.confirmedAt = now
        XCTAssertTrue(answers.isConfirmed)
        XCTAssertFalse(answers.waitingOnConfirm)
        XCTAssertFalse(Forms.needsAnswers(questions: questions, answers: answers))

        // Someone else changing them asks for the OK again.
        answers.filledBy = "alex"
        XCTAssertFalse(answers.isConfirmed)
        XCTAssertTrue(Forms.needsAnswers(questions: questions, answers: answers))

        XCTAssertTrue(Forms.needsAnswers(questions: questions, answers: nil))
        XCTAssertFalse(Forms.needsAnswers(questions: [], answers: nil))
    }

    func testQuestionsRoundTripAndClean() throws {
        let question = FormQuestion(id: "q1", kind: .choice, prompt: "  Pace?  ",
                                    options: ["Chill", "", "chill", " Packed "])
        let cleaned = question.cleaned()
        XCTAssertEqual(cleaned?.prompt, "Pace?")
        XCTAssertEqual(cleaned?.options, ["Chill", "Packed"])
        XCTAssertNil(FormQuestion(kind: .text, prompt: "   ").cleaned())
        XCTAssertEqual(FormQuestion(kind: .text, prompt: "Hi", options: ["x"]).cleaned()?.options, [])

        let encoded = try XCTUnwrap(cleaned?.encoded)
        XCTAssertEqual(FormQuestion.decode(encoded), cleaned)
        XCTAssertEqual(QuestionKind(rawValue: "yesno"), .yesNo)
    }

    func testDatesAndDisplay() {
        let day = Forms.dayString(now)
        XCTAssertEqual(day.count, 10)
        XCTAssertEqual(Forms.day(from: day).map(Forms.dayString), day)
        XCTAssertNil(Forms.day(from: "soon"))
        let yesNo = FormQuestion(kind: .yesNo, prompt: "Working?")
        XCTAssertEqual(Forms.display("yes", for: yesNo), "Yes")
        XCTAssertEqual(Forms.display("", for: yesNo), "")
    }

    func testTemplatesGetFreshIDs() {
        let first = FormTemplate.trip.makeQuestions()
        let second = FormTemplate.trip.makeQuestions()
        XCTAssertEqual(first.count, FormTemplate.trip.questions.count)
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
        XCTAssertTrue(first.contains { $0.kind == .ideas })
        for template in FormTemplate.all {
            XCTAssertTrue(template.questions.allSatisfy { $0.cleaned() != nil }, template.title)
            XCTAssertTrue(template.questions.filter { $0.kind == .choice }.allSatisfy { $0.options.count >= 2 }, template.title)
        }
    }
}
