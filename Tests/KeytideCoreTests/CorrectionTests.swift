import XCTest
@testable import KeytideCore

final class CorrectionTests: XCTestCase {
    func testQwertyMapConvertsBothDirectionsAndPreservesCase() {
        XCTAssertEqual(LayoutMap.qwerty.convert("Ghbdtn", to: .ru), "Привет")
        XCTAssertEqual(LayoutMap.qwerty.convert("Руддщ", to: .en), "Hello")
        XCTAssertNil(LayoutMap.qwerty.convert("", to: .ru))
        XCTAssertNil(LayoutMap.qwerty.convert("hello!", to: .ru))
    }

    func testDecisionRequiresUnknownOriginalAndKnownPlainAlternate() {
        let accepted = Decision.choose(
            word: "ghbdtn",
            original: WordVerdict(known: false, correction: "garden"),
            alternate: "привет",
            alternateVerdict: WordVerdict(known: true),
            protected: [],
            spelling: true
        )
        XCTAssertEqual(accepted?.replacement, "привет")
        XCTAssertEqual(accepted?.language, .ru)
        XCTAssertEqual(accepted?.kind, .layout)

        XCTAssertNil(Decision.choose(
            word: "ghbdtn",
            original: WordVerdict(known: true),
            alternate: "привет",
            alternateVerdict: WordVerdict(known: true),
            protected: [],
            spelling: true
        ))
        XCTAssertNil(Decision.choose(
            word: "ghbdtn",
            original: WordVerdict(known: false),
            alternate: "привет",
            alternateVerdict: WordVerdict(known: false),
            protected: [],
            spelling: true
        ))
        XCTAssertNil(Decision.choose(
            word: "ghbdtn",
            original: WordVerdict(known: false),
            alternate: "при-вет",
            alternateVerdict: WordVerdict(known: true),
            protected: [],
            spelling: true
        ))
    }

    func testDecisionRejectsAlternateFromTheWrongLanguage() {
        XCTAssertNil(Decision.choose(
            word: "helo",
            original: WordVerdict(known: false),
            alternate: "hello",
            alternateVerdict: WordVerdict(known: true),
            protected: [],
            spelling: false
        ))
    }

    func testDecisionRejectsProtectedOriginalAndSpellingReplacementAfterNormalization() {
        XCTAssertNil(Decision.choose(
            word: "GHBDTN",
            original: WordVerdict(known: false),
            alternate: "ПРИВЕТ",
            alternateVerdict: WordVerdict(known: true),
            protected: ["ghbdtn"],
            spelling: true
        ))
        XCTAssertEqual(Decision.choose(
            word: "GHBDTN",
            original: WordVerdict(known: false),
            alternate: "ПРИВЕТ",
            alternateVerdict: WordVerdict(known: true),
            protected: ["привет"],
            spelling: true
        )?.replacement, "ПРИВЕТ")
        XCTAssertNil(Decision.choose(
            word: "TEH",
            original: WordVerdict(known: false, correction: "THE"),
            alternate: nil,
            alternateVerdict: nil,
            protected: ["the"],
            spelling: true
        ))
    }

    func testProtectedTargetIsRecognizedWithoutSystemDictionary() {
        for (word, target) in [("kjrb", "локи"), ("Kjrb", "Локи"), ("KJRB", "ЛОКИ"),
                               ("лунешву", "keytide")] {
            XCTAssertEqual(LayoutMap.qwerty.convert(word, to: Words.language(of: target)!), target)
            let result = Decision.choose(word: word, original: WordVerdict(known: false),
                alternate: target, alternateVerdict: WordVerdict(known: false),
                protected: [Words.normalized(target)], spelling: false)
            XCTAssertEqual(result?.replacement, target)
            XCTAssertEqual(result?.kind, .layout)
            XCTAssertEqual(result?.language, Words.language(of: target))
        }
        XCTAssertNil(Decision.choose(word: "kjrb", original: WordVerdict(known: false),
            alternate: "локи", alternateVerdict: WordVerdict(known: false),
            protected: [], spelling: false))
        XCTAssertNil(Decision.choose(word: "kjrb", original: WordVerdict(known: false),
            alternate: "lo-ki", alternateVerdict: nil, protected: ["lo-ki"], spelling: false))
    }

    func testKnownOriginalWinsEvenWhenAlternateIsProtected() {
        XCTAssertNil(Decision.choose(word: "cat", original: WordVerdict(known: true),
            alternate: "сфе", alternateVerdict: WordVerdict(known: false),
            protected: ["сфе"], spelling: false))
        XCTAssertNil(Decision.choose(word: "локи", original: WordVerdict(known: false, correction: "луки"),
            alternate: "kjrb", alternateVerdict: WordVerdict(known: true),
            protected: ["локи"], spelling: true))
    }

    func testTwoLetterLayoutsPreserveCaseAndKnownOriginals() {
        for (word, target) in [("lf", "да"), ("Lf", "Да"), ("LF", "ДА"), ("ещ", "to")] {
            let result = Decision.choose(word: word, original: WordVerdict(known: false),
                alternate: target, alternateVerdict: WordVerdict(known: true),
                protected: [], spelling: false)
            XCTAssertEqual(result?.replacement, target)
            XCTAssertEqual(result?.kind, .layout)
        }
        XCTAssertNil(Decision.choose(word: "no", original: WordVerdict(known: true),
            alternate: "тщ", alternateVerdict: WordVerdict(known: true),
            protected: [], spelling: false))
        XCTAssertNil(Decision.choose(word: "lf", original: WordVerdict(known: false),
            alternate: "да", alternateVerdict: WordVerdict(known: false),
            protected: [], spelling: false))
        XCTAssertNil(Decision.choose(word: "z", original: WordVerdict(known: false),
            alternate: "я", alternateVerdict: WordVerdict(known: true),
            protected: [], spelling: false))
    }

    func testSpellingDecisionPreservesUpperTitleAndLowerCase() {
        XCTAssertEqual(spellingReplacement(word: "TEH", suggestion: "the"), "THE")
        XCTAssertEqual(spellingReplacement(word: "Teh", suggestion: "the"), "The")
        XCTAssertEqual(spellingReplacement(word: "teh", suggestion: "THE"), "the")
    }

    func testSpellingDecisionRejectsMixedCaseProperNoun() {
        XCTAssertNil(spellingReplacement(word: "GitHib", suggestion: "github"))
    }

    func testSpellingDecisionRejectsDisabledMixedScriptAndDistantSuggestion() {
        XCTAssertNil(spellingReplacement(word: "teh", suggestion: "the", enabled: false))
        XCTAssertNil(spellingReplacement(word: "tеh", suggestion: "the"))
        XCTAssertNil(spellingReplacement(word: "cat", suggestion: "dog"))
        XCTAssertNil(spellingReplacement(word: "cat", suggestion: "кот"))
    }

    func testOneEditApartCoversEachAcceptedEditAndRejectsAmbiguousCases() {
        XCTAssertTrue(Words.oneEditApart("cat", "cut"))
        XCTAssertTrue(Words.oneEditApart("cat", "cart"))
        XCTAssertTrue(Words.oneEditApart("cart", "cat"))
        XCTAssertTrue(Words.oneEditApart("teh", "the"))
        XCTAssertFalse(Words.oneEditApart("cat", "cat"))
        XCTAssertFalse(Words.oneEditApart("cat", "dog"))
        XCTAssertFalse(Words.oneEditApart("abcd", "badc"))
        XCTAssertFalse(Words.oneEditApart("e\u{301}", "é"))
    }

    func testDecisionEnforcesWordLengthBoundaries() {
        XCTAssertNil(spellingReplacement(word: "ab", suggestion: "ac"))

        let withinLimit = String(repeating: "a", count: Words.maximumLength - 1) + "b"
        let withinSuggestion = String(repeating: "a", count: Words.maximumLength - 1) + "c"
        XCTAssertEqual(spellingReplacement(word: withinLimit, suggestion: withinSuggestion), withinSuggestion)

        let overLimit = String(repeating: "a", count: Words.maximumLength) + "b"
        let overSuggestion = String(repeating: "a", count: Words.maximumLength) + "c"
        XCTAssertNil(spellingReplacement(word: overLimit, suggestion: overSuggestion))
    }

    private func spellingReplacement(word: String, suggestion: String, enabled: Bool = true) -> String? {
        Decision.choose(
            word: word,
            original: WordVerdict(known: false, correction: suggestion),
            alternate: nil,
            alternateVerdict: nil,
            protected: [],
            spelling: enabled
        )?.replacement
    }
}
