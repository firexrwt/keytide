import Foundation
import XCTest
@testable import KeytideCore

// The field "one рфму |" (caret after the space at 9): the word is at 4..<8.
final class RollbackTests: XCTestCase {
    private let range = NSRange(location: 4, length: 4), caret = NSRange(location: 9, length: 0)

    private func accepts(_ shown: String, selected: NSRange?, boundary: String? = " ") -> Bool {
        Rollback.accepts(word: "рфму", range: range, caret: caret, shown: shown, selected: selected, boundary: boundary)
    }

    func testTheSameWordOrARecaseRollsBack() {
        XCTAssertTrue(accepts("рфму", selected: nil, boundary: nil))
        XCTAssertTrue(accepts("Рфму", selected: nil, boundary: nil))
    }

    func testASameLengthRewriteRollsBackWhereTheSelectionStayed() {
        XCTAssertTrue(accepts("раму", selected: range), "Keytide's own selection")
        XCTAssertTrue(accepts("раму", selected: NSRange(location: 8, length: 0)), "the caret after the word")
        XCTAssertTrue(accepts("раму", selected: caret), "the caret already put back")
    }

    // Security review of 0.1.7: a positional check alone accepted these, and held keys would land mid-text.
    func testTextThatMovedRefusesTheRollback() {
        XCTAssertFalse(accepts("раму", selected: NSRange(location: 7, length: 4)), "text inserted before the word")
        XCTAssertFalse(accepts("so m", selected: NSRange(location: 4, length: 7)), "one word expanded into several")
        XCTAssertFalse(accepts("раму", selected: nil), "selection unreadable")
    }

    func testALongerOrShorterRewriteRefusesTheRollback() {
        XCTAssertFalse(accepts("рамк", selected: range, boundary: "у"), "longer: the boundary is a letter now")
        XCTAssertFalse(accepts("рам ", selected: range), "shorter: the range holds the space")
        XCTAssertFalse(accepts("раму", selected: range, boundary: nil), "boundary unreadable")
    }
}
