import Foundation
import XCTest
@testable import KeytideCore

final class WordRangeTests: XCTestCase {
    func testPrecedingUsesUTF16OffsetsForUnicodePrefix() {
        let result = WordRange.preceding(in: "😀 привет ", offset: 40, requireBoundary: true)

        XCTAssertEqual(result?.word, "привет")
        XCTAssertEqual(result?.range, NSRange(location: 43, length: 6))
    }

    // The whole run before the space, punctuation included: punctuation keys are letters in the other layout.
    func testPrecedingReturnsTheWholeRunBeforeWhitespace() {
        let result = WordRange.preceding(in: "hello!!! ", offset: 0, requireBoundary: true)
        XCTAssertEqual(result, WordRange(word: "hello!!!", range: NSRange(location: 0, length: 8)))
        XCTAssertEqual(WordRange.preceding(in: "one yj; ", offset: 0, requireBoundary: true)?.word, "yj;")
        XCTAssertEqual(WordRange.preceding(in: "one >kbnm ", offset: 0, requireBoundary: true)?.word, ">kbnm")
        XCTAssertEqual(WordRange.preceding(in: "one \u{2018}[jv ", offset: 0, requireBoundary: true)?.word, "\u{2018}[jv")
    }

    func testPrecedingReadsCurrentWordWhenBoundaryIsNotRequired() {
        let result = WordRange.preceding(in: "say hello", offset: 0, requireBoundary: false)

        XCTAssertEqual(result, WordRange(word: "hello", range: NSRange(location: 4, length: 5)))
    }

    func testPrecedingRejectsWordThatMayBeTruncatedAtWindowStart() {
        XCTAssertNil(WordRange.preceding(in: "hello ", offset: 10, requireBoundary: true))

        let bounded = WordRange.preceding(in: " hello ", offset: 10, requireBoundary: true)
        XCTAssertEqual(bounded, WordRange(word: "hello", range: NSRange(location: 11, length: 5)))
    }

    func testPrecedingRejectsMissingBoundaryAndHostileInputs() {
        XCTAssertNil(WordRange.preceding(in: "hello", offset: 0, requireBoundary: true))
        XCTAssertNil(WordRange.preceding(in: "hello😀 ", offset: 0, requireBoundary: true))
        XCTAssertNil(WordRange.preceding(in: "", offset: 0, requireBoundary: false))
        XCTAssertNil(WordRange.preceding(in: "hello ", offset: -1, requireBoundary: true))
    }

    func testPrecedingEnforcesUTF16WindowAndWordLimits() {
        let exactWindow = String(repeating: " ", count: 154) + "hello "
        XCTAssertEqual((exactWindow as NSString).length, 160)
        XCTAssertEqual(WordRange.preceding(in: exactWindow, offset: 0, requireBoundary: true)?.word, "hello")

        let oversizedWindow = " " + exactWindow
        XCTAssertEqual((oversizedWindow as NSString).length, 161)
        XCTAssertNil(WordRange.preceding(in: oversizedWindow, offset: 0, requireBoundary: true))

        let maximumWord = String(repeating: "a", count: Words.maximumLength) + " "
        XCTAssertEqual(WordRange.preceding(in: maximumWord, offset: 0, requireBoundary: true)?.word,
                       String(repeating: "a", count: Words.maximumLength))
        XCTAssertNil(WordRange.preceding(
            in: String(repeating: "a", count: Words.maximumLength + 1) + " ",
            offset: 0,
            requireBoundary: true
        ))
    }
}
