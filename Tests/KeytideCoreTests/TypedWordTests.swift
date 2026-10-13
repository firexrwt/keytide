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
        XCTAssertEqual(word.finish(), Retype(run: "ghbdtn"))
        XCTAssertNil(word.finish())
        word.append("l"); word.append("f")
        XCTAssertEqual(word.finish()?.run,"lf")
    }

    func testDeleteBackwardEditsWordAndEmptyDeleteKeepsTracking() {
        var word = typed("ghbdtnn")
        word.deleteBackward()
        XCTAssertEqual(word.current, "ghbdtn")
        // Deleting a whole word and its space, then retyping it: only the retyped characters are ever deleted later.
        var older = TypedWord()
        older.deleteBackward(); older.deleteBackward()
        older.append("l"); older.append("f")
        XCTAssertEqual(older.finish()?.run,"lf")
    }

    func testInvalidateHoldsUntilBoundaryAndRestartClears() {
        var word = typed("ghb")
        word.invalidate(); word.append("d")
        XCTAssertNil(word.finish())
        var line = typed("ghb")
        line.invalidate(); line.restart(); line.append("l"); line.append("f")
        XCTAssertEqual(line.finish()?.run,"lf")
    }

    func testNonTextKeysStartANewWord() {
        // Arrows, Escape, Tab, Delete: the caret or the field changed, the next characters start a new word.
        for text in ["\u{F702}", "\u{1B}", "\t", " ", "\u{7F}"] {
            var word = typed("gh")
            word.append(text)
            word.append("l"); word.append("f")
            XCTAssertEqual(word.finish()?.run,"lf", "\(text.unicodeScalars.map(\.value))")
        }
    }

    // Edit guard: a word started where the key stream did not see the text before it may be part of a longer word.
    func testCaretMovesMarkTheNextWordAsEdited() {
        // Left arrow, Home, Escape, forward Delete.
        for text in ["\u{F702}", "\u{F729}", "\u{1B}", "\u{7F}"] {
            var word = typed("gh")
            word.append(text)
            word.append("l"); word.append("f")
            XCTAssertEqual(word.finish()?.run,"lf")
            XCTAssertTrue(word.finishedAfterEdit, "\(text.unicodeScalars.map(\.value))")
            word.append("d"); word.append("f")
            XCTAssertEqual(word.finish()?.run,"df")
            XCTAssertFalse(word.finishedAfterEdit, "the boundary re-synchronizes the word with the field")
        }
    }

    func testBackspacePastTheWordStartAndClicksMarkEdited() {
        var word = TypedWord()
        word.deleteBackward()
        word.append("l"); word.append("f")
        _ = word.finish()
        XCTAssertTrue(word.finishedAfterEdit)
        var inside = typed("ghbdtnn")
        inside.deleteBackward()
        _ = inside.finish()
        XCTAssertFalse(inside.finishedAfterEdit, "Backspace inside the typed word is tracked exactly")
        var clicked = typed("gh")
        clicked.relocate(); clicked.append("l"); clicked.append("f")
        XCTAssertEqual(clicked.finish()?.run,"lf")
        XCTAssertTrue(clicked.finishedAfterEdit)
    }

    func testOnlyUnreadableCharactersMakeAFinishedWordUnknown() {
        var unknown = typed("lf")
        _ = unknown.key(5, [], text: nil)
        XCTAssertNil(unknown.finish())
        XCTAssertTrue(unknown.finishedUnknown, "only a readable field can name this word")
        var empty = TypedWord()
        XCTAssertNil(empty.finish())
        XCTAssertFalse(empty.finishedUnknown, "a double space has nothing to look up")
    }

    func testCleanStartsClearTheEditMark() {
        // Return, Tab or a typed space: the next word starts at a boundary the user typed.
        var restarted = TypedWord()
        restarted.relocate(); restarted.restart(); restarted.append("l"); restarted.append("f")
        _ = restarted.finish()
        XCTAssertFalse(restarted.finishedAfterEdit)
        var line = TypedWord()
        line.relocate(); _ = line.key(36, [], text: self.unexpectedText()); line.append("l")
        _ = line.finish()
        XCTAssertFalse(line.finishedAfterEdit)
        for text in ["\t", " "] {
            var word = TypedWord()
            word.relocate(); word.append(text); word.append("l")
            _ = word.finish()
            XCTAssertFalse(word.finishedAfterEdit, "\(text.unicodeScalars.map(\.value))")
        }
    }

    func testKeyWithoutCharactersLeavesWordUnchanged() {
        // fn / Globe switches the layout as key code 179 with an empty string.
        var word = typed("lf")
        XCTAssertNil(word.key(179, [], text: ""))
        XCTAssertEqual(word.finish()?.run,"lf")
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

    // Punctuation keys are letters in the other layout ("yj;" is "нож"): the whole run is replaced, punctuation and all.
    func testTheWholeRunIsReplacedPunctuationIncluded() {
        var word = typed("ghbdtn?!")
        let retype = word.finish()
        XCTAssertEqual(retype, Retype(run: "ghbdtn?!"))
        XCTAssertEqual(retype?.deletions, 9)
        XCTAssertEqual(retype?.text("привет,!"), "привет,! ")
        var inner = typed("hf,jnf")
        XCTAssertEqual(inner.finish(), Retype(run: "hf,jnf"))
    }

    func testTracksCyrillicLikeLatin() {
        var word = typed("руддщ")
        word.deleteBackward()
        XCTAssertEqual(word.finish(), Retype(run: "рудд"))
    }

    func testDeletionsCoverWordAndBoundarySpace() {
        XCTAssertEqual(Retype(run: "lf").deletions, 3)
        XCTAssertEqual(Retype(run: "lf").text("да"), "да ")
    }

    func testKeyMapsBoundariesEditsAndShortcuts() {
        var word = TypedWord()
        XCTAssertNil(word.key(5, [], text: "g"))
        XCTAssertNil(word.key(4, [], text: "h"))
        XCTAssertEqual(word.key(49, .shift, text: self.unexpectedText()), Retype(run: "gh"))
        _ = word.key(37, [], text: "l"); _ = word.key(3, [], text: "f")
        _ = word.key(51, [], text: self.unexpectedText())
        XCTAssertEqual(word.current, "l")
        _ = word.key(36, [], text: self.unexpectedText())
        XCTAssertNil(word.current, "Return starts a known empty word")
        _ = word.key(37, [], text: "l"); _ = word.key(3, [], text: "f")
        XCTAssertEqual(word.key(49, [], text: " ")?.run,"lf")
        _ = word.key(37, [], text: "l")
        _ = word.key(2, .control, text: self.unexpectedText())
        XCTAssertNil(word.key(49, [], text: " "), "a shortcut may edit the field: what came before it is dropped")
        _ = word.key(37, [], text: "l")
        XCTAssertNil(word.key(49, .command, text: self.unexpectedText()), "Cmd+Space is not a boundary")
        // Letters typed after a chord (Cmd+Space opening Raycast, Cmd+A) are a known run, marked as an edit.
        _ = word.key(37, [], text: "l"); _ = word.key(3, [], text: "f")
        XCTAssertEqual(word.key(49, [], text: " ")?.run,"lf")
        XCTAssertTrue(word.finishedAfterEdit)
    }
}
