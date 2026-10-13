import XCTest
@testable import KeytideCore

final class TypedInFieldTests: XCTestCase {
    private let typed = Retype(run: "ghbdtn")

    func testTheTypedWordIsWholeWhereverItStands() {
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn ", fromFieldStart: true, typed: typed), .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "one two ghbdtn ", fromFieldStart: false, typed: typed), .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "line\nghbdtn ", fromFieldStart: false, typed: typed), .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn?! ", fromFieldStart: true,
                                            typed: Retype(run: "ghbdtn?!")), .same)
    }

    func testContenteditableNoBreakSpacesCountAsSpaces() {
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn\u{00A0}", fromFieldStart: true, typed: typed), .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "one\u{00A0}ghbdtn\u{00A0}", fromFieldStart: false, typed: typed), .same)
    }

    func testTypingTheEndOfAnExistingWordTakesTheWholeWord() {
        // Clicked after "gh" in the text and typed "bdtn ": the word in the field is "ghbdtn".
        XCTAssertEqual(TypedInField.resolve(prefix: "one ghbdtn ", fromFieldStart: true,
                                            typed: Retype(run: "bdtn")),
                       .whole(Retype(run: "ghbdtn")))
        XCTAssertEqual(TypedInField.resolve(prefix: "ghbdtn! ", fromFieldStart: true, typed: Retype(run: "n!")),
                       .whole(Retype(run: "ghbdtn!")))
    }

    // Notes and TextEdit turn the typed "'" and "\"" (э, Э) into smart quotes: still the typed run.
    func testSmartQuotesInTheFieldAreTheTypedQuoteKeys() {
        XCTAssertEqual(TypedInField.resolve(prefix: "one \u{2018}[jv ", fromFieldStart: false, typed: Retype(run: "'[jv")),
                       .same)
        XCTAssertEqual(TypedInField.resolve(prefix: "one \u{201C}[jv ", fromFieldStart: false, typed: Retype(run: "[jv")),
                       .whole(Retype(run: "\"[jv")))
    }

    func testAWordTheKeysCouldNotShowComesFromTheField() {
        // After a chord (select all, paste) the key stream does not know the word; the field does.
        let unknown = Retype(run: "")
        XCTAssertEqual(TypedInField.resolve(prefix: "one ghbdtn ", fromFieldStart: false, typed: unknown),
                       .whole(Retype(run: "ghbdtn")))
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
        XCTAssertEqual(TypedInField.resolve(prefix: "hbdtn ", fromFieldStart: false, typed: Retype(run: "dtn")),
                       .changed)
        let long = String(repeating: "a", count: Words.maximumLength + 1)
        XCTAssertEqual(TypedInField.resolve(prefix: long + " ", fromFieldStart: true, typed: Retype(run: "a")),
                       .changed)
    }

    func testOnlyAWordAfterAnEditOrAnUnknownWordReadsTheField() {
        XCTAssertFalse(WordChoice.needsField(typed, edited: false))
        XCTAssertTrue(WordChoice.needsField(typed, edited: true))
        XCTAssertTrue(WordChoice.needsField(Retype(run: ""), edited: false))
    }

    // Owner rule: position never decides. A word started after a click is corrected even where the field is silent.
    func testAWordAfterAnEditIsCorrectedEvenWhenTheFieldCannotBeRead() {
        XCTAssertEqual(WordChoice.choose(.unanswered, typed: typed, last: false, treeRequested: false), .typed)
        XCTAssertEqual(WordChoice.choose(.unanswered, typed: typed, last: true, treeRequested: true), .typed)
        XCTAssertEqual(WordChoice.choose(.read(.pending), typed: typed, last: true, treeRequested: false), .typed)
    }

    func testTheFieldNamesTheWholeWordOrVetoes() {
        let whole = Retype(run: "pdtplysq")
        XCTAssertEqual(WordChoice.choose(.read(.same), typed: typed, last: false, treeRequested: false), .field(typed))
        XCTAssertEqual(WordChoice.choose(.read(.whole(whole)), typed: typed, last: false, treeRequested: false), .field(whole))
        XCTAssertEqual(WordChoice.choose(.read(.changed), typed: typed, last: false, treeRequested: false),
                       .skip("field shows another word"))
        XCTAssertEqual(WordChoice.choose(.refused("secure field"), typed: typed, last: false, treeRequested: false),
                       .skip("secure field"))
    }

    func testASlowFieldGetsExactlyOneMoreLook() {
        XCTAssertEqual(WordChoice.choose(.read(.pending), typed: typed, last: false, treeRequested: false), .again(0.04))
        XCTAssertEqual(WordChoice.choose(.unanswered, typed: typed, last: false, treeRequested: true), .again(0.15))
    }

    func testAWordTheKeysCouldNotShowNeedsTheField() {
        let empty = Retype(run: "")
        XCTAssertEqual(WordChoice.choose(.unanswered, typed: empty, last: true, treeRequested: false), .skip("no typed word"))
        XCTAssertEqual(WordChoice.choose(.read(.whole(typed)), typed: empty, last: false, treeRequested: false), .field(typed))
    }
}
