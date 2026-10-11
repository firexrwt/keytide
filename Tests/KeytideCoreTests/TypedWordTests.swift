import XCTest
@testable import KeytideCore

final class TypedWordTests: XCTestCase {
    private func typed(_ text: String) -> TypedWord {
        var word = TypedWord()
        for character in text { word.append(String(character)) }
        return word
    }

    private func unexpectedText() -> String {
        XCTFail("the key string was read for a non-character key")
        return ""
    }

    func testFinishReturnsWordAndRestarts() {
        var word = typed("ghbdtn")
        XCTAssertEqual(word.finish(), Retype(word: "ghbdtn", suffix: ""))
        XCTAssertNil(word.finish())
        word.append("l"); word.append("f")
        XCTAssertEqual(word.finish()?.word, "lf")
    }

    func testDeleteBackwardEditsWordAndEmptyDeleteKeepsTracking() {
        var word = typed("ghbdtnn")
        word.deleteBackward()
        XCTAssertEqual(word.current, "ghbdtn")
        // Deleting a whole word and its space, then retyping it: only the retyped characters are ever deleted later.
        var older = TypedWord()
        older.deleteBackward(); older.deleteBackward()
        older.append("l"); older.append("f")
        XCTAssertEqual(older.finish()?.word, "lf")
    }

    func testInvalidateHoldsUntilBoundaryAndRestartClears() {
        var word = typed("ghb")
        word.invalidate(); word.append("d")
        XCTAssertNil(word.finish())
        var line = typed("ghb")
        line.invalidate(); line.restart(); line.append("l"); line.append("f")
        XCTAssertEqual(line.finish()?.word, "lf")
    }

    func testNonTextKeysStartANewWord() {
        // Arrows, Escape, Tab, Delete: the caret or the field changed, the next characters start a new word.
        for text in ["\u{F702}", "\u{1B}", "\t", " ", "\u{7F}"] {
            var word = typed("gh")
            word.append(text)
            word.append("l"); word.append("f")
            XCTAssertEqual(word.finish()?.word, "lf", "\(text.unicodeScalars.map(\.value))")
        }
    }

    func testKeyWithoutCharactersLeavesWordUnchanged() {
        // fn / Globe switches the layout as key code 179 with an empty string.
        var word = typed("lf")
        XCTAssertNil(word.key(179, [], text: ""))
        XCTAssertEqual(word.finish()?.word, "lf")
    }

    func testUnreadableKeyStringMakesWordUnknown() {
        var word = typed("lf")
        XCTAssertNil(word.key(5, [], text: nil))
        word.append("l"); word.append("f")
        XCTAssertNil(word.finish(), "characters the app received are unknown, so no count of Backspaces is safe")
    }

    func testKeyWithSeveralCharactersAppendsAll() {
        var word = typed("l")
        word.append("fx")
        XCTAssertEqual(word.finish()?.deletions, 4)
    }

    func testCapacityMatchesWordLimit() {
        var word = typed(String(repeating: "a", count: Words.maximumLength))
        XCTAssertEqual(word.current?.count, Words.maximumLength)
        word.append("a")
        XCTAssertNil(word.finish())
    }

    func testSplitsTrailingPunctuationLikeWordRange() {
        var word = typed("ghbdtn?!")
        let retype = word.finish()
        XCTAssertEqual(retype, Retype(word: "ghbdtn", suffix: "?!"))
        XCTAssertEqual(retype?.deletions, 9)
        XCTAssertEqual(retype?.text("привет"), "привет?! ")
        var inner = typed("hf,jnf")
        XCTAssertEqual(inner.finish(), Retype(word: "hf,jnf", suffix: ""))
        var only = typed("?!")
        XCTAssertNil(only.finish())
    }

    func testTracksCyrillicLikeLatin() {
        var word = typed("руддщ")
        word.deleteBackward()
        XCTAssertEqual(word.finish(), Retype(word: "рудд", suffix: ""))
    }

    func testDeletionsCoverWordAndBoundarySpace() {
        XCTAssertEqual(Retype(word: "lf", suffix: "").deletions, 3)
        XCTAssertEqual(Retype(word: "lf", suffix: "").text("да"), "да ")
    }

    func testKeyMapsBoundariesEditsAndShortcuts() {
        var word = TypedWord()
        XCTAssertNil(word.key(5, [], text: "g"))
        XCTAssertNil(word.key(4, [], text: "h"))
        XCTAssertEqual(word.key(49, .shift, text: self.unexpectedText()), Retype(word: "gh", suffix: ""))
        _ = word.key(37, [], text: "l"); _ = word.key(3, [], text: "f")
        _ = word.key(51, [], text: self.unexpectedText())
        XCTAssertEqual(word.current, "l")
        _ = word.key(36, [], text: self.unexpectedText())
        XCTAssertNil(word.current, "Return starts a known empty word")
        _ = word.key(37, [], text: "l"); _ = word.key(3, [], text: "f")
        XCTAssertEqual(word.key(49, [], text: " ")?.word, "lf")
        _ = word.key(37, [], text: "l")
        _ = word.key(2, .control, text: self.unexpectedText())
        XCTAssertNil(word.key(49, [], text: " "), "a shortcut may edit the field")
        _ = word.key(37, [], text: "l")
        XCTAssertNil(word.key(49, .command, text: self.unexpectedText()), "Cmd+Space is not a boundary")
        _ = word.key(37, [], text: "l"); _ = word.key(3, [], text: "f")
        XCTAssertNil(word.key(49, [], text: " "), "the word stays unknown until a plain space")
    }
}
