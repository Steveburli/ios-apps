import XCTest
@testable import MutualKit

final class CardImportTests: XCTestCase {
    func testLinesSplitAtDashOrComma() {
        let drafts = CardImport.parse("""
        1. Thai Basil - great pad see ew
        • Crouching Tiger, Hidden Dragon - 2000
        Pizza King, cheap and close
        Plain title
        """)
        XCTAssertEqual(drafts.map(\.title), ["Thai Basil", "Crouching Tiger, Hidden Dragon", "Pizza King", "Plain title"])
        XCTAssertEqual(drafts.map(\.details), ["great pad see ew", "2000", "cheap and close", ""])
    }

    func testBarsStillWork() {
        let drafts = CardImport.parse("Sunset picnic | $ · 2 hours | Takeout and a blanket | example.com")
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].subtitle, "$ · 2 hours")
        XCTAssertEqual(drafts[0].details, "Takeout and a blanket")
        XCTAssertEqual(drafts[0].link, "https://example.com")
    }

    func testAIAnswerChatterIsDropped() {
        let answer = """
        Here are some movies streaming for free:

        ```
        **Clue** | 1985 · comedy | A dinner party murder mystery. |
        Arrival | 2016 · sci-fi | Linguist meets aliens. | https://example.com/arrival
        Paddington 2 | 2017 · family | A bear in prison. |
        ```
        Enjoy your movie night!
        """
        XCTAssertEqual(CardImport.parse(answer).map(\.title), ["Clue", "Arrival", "Paddington 2"])
    }

    func testMarkdownTable() {
        let table = """
        | Title | Quick facts |
        |---|---|
        | Clue | 1985 |
        | Arrival | 2016 |
        """
        XCTAssertEqual(CardImport.parse(table).map(\.title), ["Clue", "Arrival"])
    }

    func testCSVWithHeader() {
        let csv = "Name,Description,Website,Tags\n\"Shapiro's, Downtown\",\"Deli, \"\"huge\"\" sandwiches\",shapiros.com,deli; lunch\nMilktooth,Brunch,,brunch\n"
        let drafts = CardImport.parse(csv)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].title, "Shapiro's, Downtown")
        XCTAssertEqual(drafts[0].details, "Deli, \"huge\" sandwiches")
        XCTAssertEqual(drafts[0].link, "https://shapiros.com")
        XCTAssertEqual(drafts[0].tags, ["deli", "lunch"])
        XCTAssertEqual(drafts[1].title, "Milktooth")
    }

    func testCSVWithoutHeaderUsesColumnOrder() {
        let drafts = CardImport.parse("Clue,1985,Mystery\r\nArrival,2016,Sci-fi\r\n", isCSV: true)
        XCTAssertEqual(drafts.map(\.title), ["Clue", "Arrival"])
        XCTAssertEqual(drafts.map(\.subtitle), ["1985", "2016"])
    }

    func testTabSeparatedFromASpreadsheet() {
        let drafts = CardImport.parse("Title\tDetails\nClue\tMystery\n")
        XCTAssertEqual(drafts.map(\.title), ["Clue"])
        XCTAssertEqual(drafts.map(\.details), ["Mystery"])
    }

    func testPromptNamesTheRequest() {
        let prompt = CardImport.aiPrompt(for: "most popular free movies", kind: .movies, deckTitle: "Movie night")
        XCTAssertTrue(prompt.contains("most popular free movies"))
        XCTAssertTrue(prompt.contains("Title | quick facts"))
    }
}
