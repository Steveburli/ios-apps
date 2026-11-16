import XCTest
@testable import MutualKit

final class CardPhotosTests: XCTestCase {
    private func photo(_ id: String, order: Double) -> CardPhoto {
        CardPhoto(id: id, groupID: "g", deckID: "d", cardID: "c", order: order, addedBy: "", createdAt: Date())
    }

    func testSortedByOrderThenID() {
        let photos = [photo("b", order: 2), photo("c", order: 1), photo("a", order: 2)]
        XCTAssertEqual(CardPhotos.sorted(photos).map(\.id), ["c", "a", "b"])
    }

    func testRoomStopsAtSix() {
        XCTAssertEqual(CardPhotos.limit, 6)
        XCTAssertEqual(CardPhotos.room(after: 0), 6)
        XCTAssertEqual(CardPhotos.room(after: 4), 2)
        XCTAssertEqual(CardPhotos.room(after: 6), 0)
        XCTAssertEqual(CardPhotos.room(after: 9), 0)
    }

    func testFittedSizeShrinksTheLongestSide() {
        let wide = CardPhotos.fittedSize(width: 4032, height: 3024)
        XCTAssertEqual(wide.width, 1280)
        XCTAssertEqual(wide.height, 960)
        let tall = CardPhotos.fittedSize(width: 3024, height: 4032)
        XCTAssertEqual(tall.width, 960)
        XCTAssertEqual(tall.height, 1280)
        let small = CardPhotos.fittedSize(width: 800, height: 600)
        XCTAssertEqual(small.width, 800)
        XCTAssertEqual(small.height, 600)
    }

    func testMapsURLSearchesForTheTitle() {
        let card = Card(groupID: "g", deckID: "d", draft: CardDraft(title: "St. Elmo Steak House"), order: 0, createdAt: Date())
        XCTAssertEqual(CardPhotos.mapsURL(for: card)?.absoluteString,
                       "https://www.google.com/maps/search/?api=1&query=St.%20Elmo%20Steak%20House")
        let blank = Card(groupID: "g", deckID: "d", draft: CardDraft(title: "  "), order: 0, createdAt: Date())
        XCTAssertNil(CardPhotos.mapsURL(for: blank))
    }

    func testPhotoIDsAreSafeRecordNames() {
        let id = CardPhoto(groupID: "g", deckID: "d", cardID: "c", order: 0, addedBy: "", createdAt: Date()).id
        XCTAssertTrue(id.hasPrefix("photo_"))
        XCTAssertNil(id.range(of: "[^a-z0-9_]", options: .regularExpression))
    }
}
