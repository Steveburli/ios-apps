import XCTest
@testable import OMMKit

final class CatalogTests: XCTestCase {
    func testGridShape() {
        XCTAssertEqual(Catalog.rows.map(\.area), ["Core", "Thighs", "Calves", "Chest", "Back", "Shoulders", "Arms"])
        XCTAssertTrue(Catalog.rows.allSatisfy { $0.groups.count == 4 })
        XCTAssertEqual(Catalog.groups.count, 28)
    }

    func testCategoryCounts() {
        XCTAssertEqual(Catalog.groups.filter { $0.category == .upper }.count, 16)
        XCTAssertEqual(Catalog.groups.filter { $0.category == .lower }.count, 8)
        XCTAssertEqual(Catalog.groups.filter { $0.category == .core }.count, 4)
    }

    func testKeysAreUniqueAndInnerIsSplit() {
        XCTAssertEqual(Set(Catalog.groups.map(\.key)).count, 28)
        XCTAssertEqual(Catalog.group("Inner (Thighs)")?.area, "Thighs")
        XCTAssertEqual(Catalog.group("Inner (Chest)")?.area, "Chest")
        XCTAssertEqual(Catalog.group("Inner (Chest)")?.name, "Inner")
        XCTAssertNil(Catalog.group("Inner"))
    }

    func testEveryGroupHasFivePlusFiveExercises() {
        for group in Catalog.groups {
            XCTAssertEqual(group.noEquipment.count, 5, group.key)
            XCTAssertEqual(group.gym.count, 5, group.key)
        }
    }

    func testTotalSets() {
        // 16 × 3 + 8 × 6 + 4 × 12
        XCTAssertEqual(Catalog.totalSets, 144)
    }

    func testExerciseSplit() {
        let withNote = ExerciseText.split("Step-Ups (on a sturdy chair)")
        XCTAssertEqual(withNote.title, "Step-Ups")
        XCTAssertEqual(withNote.note, "on a sturdy chair")

        let middle = ExerciseText.split("Plyometric (Clapping) Push-ups")
        XCTAssertEqual(middle.title, "Plyometric (Clapping) Push-ups")
        XCTAssertNil(middle.note)

        let plain = ExerciseText.split("Dumbbell \"Cuban Press\"")
        XCTAssertEqual(plain.title, "Dumbbell \"Cuban Press\"")
        XCTAssertNil(plain.note)

        let lastParens = ExerciseText.split("Glute-Ham Raise (GHR) Bench")
        XCTAssertNil(lastParens.note)
    }
}
