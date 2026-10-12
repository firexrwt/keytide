import XCTest
@testable import KeytideCore

final class TypedInFieldTests: XCTestCase {
    private let typed = Retype(word: "ghbdtn", suffix: "")

    func testTheTypedWordIsWholeWhereverItStands() {
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn ", fromFieldStart: true, typed: typed), .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "one two ghbdtn ", fromFieldStart: false, typed: typed), .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "line\nghbdtn ", fromFieldStart: false, typed: typed), .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn?! ", fromFieldStart: true,
                                            typed: Retype(word: "ghbdtn", suffix: "?!")), .same)
    }

    func testContenteditableNoBreakSpacesCountAsSpaces() {
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn\u{00A0}", fromFieldStart: true, typed: typed), .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "one\u{00A0}ghbdtn\u{00A0}", fromFieldStart: false, typed: typed), .same)
    }

    func testTypingTheEndOfAnExistingWordTakesTheWholeWord() {
        // Clicked after "gh" in the text and typed "bdtn ": the word in the field is "ghbdtn".
        XCTAssertEqual(TypedInField.resolve(prefix: "one ghbdtn ", fromFieldStart: true,
                                            typed: Retype(word: "bdtn", suffix: "")),
                       .whole(Retype(word: "ghbdtn", suffix: "")))
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn! ", fromFieldStart: true, typed: Retype(word: "n", suffix: "!")),
                       .whole(Retype(word: "ghbdtn", suffix: "!")))
    }

    func testAWordTheKeysCouldNotShowComesFromTheField() {
        // After a chord (select all, paste) the key stream does not know the word; the field does.
        let unknown = Retype(word: "", suffix: "")
        XCTAssertEqual(TypedInField.resolve(prefix: "one ghbdtn ", fromFieldStart: false, typed: unknown),
                       .whole(Retype(word: "ghbdtn", suffix: "")))
        XCTAssertEqual(TypedInField.resolve(prefix: "one  ", fromFieldStart: true, typed: unknown), .changed)
        XCTAssertEqual(TypedInField.resolve(prefix: " ", fromFieldStart: true, typed: unknown), .changed)
    }

    func testAFieldThatDoesNotEndWithTheTypedRunRefuses() {
        // The app rewrote the word on the same space (autocorrect, recasing, text replacement).
        XCTAssertEqual(TypedInField.resolve(prefix: "Ghbdtn ", fromFieldStart: true, typed: typed), .changed)
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn. ", fromFieldStart: true, typed: typed), .changed)
        XCTAssertEqual(TypedInField.resolve(prefix: "dtn ", fromFieldStart: true, typed: typed), .changed)
        XCTAssertEqual(TypedInField.resolve(prefix: "", fromFieldStart: true, typed: typed), .changed)
    }

    func testAFieldWithoutTheSpaceYetIsPending() {
        // Electron applies key events to its accessibility text a few milliseconds late.
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn", fromFieldStart: true, typed: typed), .pending)
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbd", fromFieldStart: true, typed: typed), .pending)
    }

    func testAWordCutByTheReadWindowIsUnknown() {
        // The read starts mid-word: the start of the word is not known, so nothing is replaced.
        XCTAssertEqual(TypedInField.resolve(prefix: "hbdtn ", fromFieldStart: false, typed: Retype(word: "dtn", suffix: "")),
                       .changed)
        let long = String(repeating: "a", count: Words.maximumLength + 1)
        XCTAssertEqual(TypedInField.resolve(prefix: long + " ", fromFieldStart: true, typed: Retype(word: "a", suffix: "")),
                       .changed)
    }
}
