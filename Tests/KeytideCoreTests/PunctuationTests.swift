import XCTest
@testable import KeytideCore

// Issue #1: punctuation keys are letters in the other layout (х ъ ж э б ю and capitals), and sentence punctuation
// sits on other keys (Apple Russian: "." on Shift+7, "," on Shift+6; Russian - PC: both on "/"). The whole run is
// converted and replaced; only the "is it already a word" check reads the run as typed.
final class PunctuationTests: XCTestCase {
    // Apple "Russian" against US, from UCKeyTranslate on this Mac (plain and Shift, keys that differ).
    private let apple: LayoutMap = {
        let english = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.\\QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>|@#$%^&*")
        let russian = Array("йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ\"№%:,.;")
        return LayoutMap(englishToRussian: Dictionary(uniqueKeysWithValues: zip(english, russian)),
                         russianToEnglish: Dictionary(uniqueKeysWithValues: zip(russian, english)))
    }()
    private let known: Set<String> = ["юлить", "эхом", "нож", "но", "привет", "hello", "их", "b", "это", "пою", "по",
                                      "люблю", "бы", "no", "let's", "e", "tea", "ну", "ye", "p", "y", "t", "c",
                                      "a", "зю", "ню", "ею", "сб", "крыж", "уж", "эф", "кп", "the", "херу", "then",
                                      "берут", "h", "юр", "эе", "пр", "iphone", "droid", "же", "nj", "jv", "er",
                                      "жук", "бока", "rf"]

    private func fix(_ run: String, _ map: LayoutMap = .qwerty, suggestion: String? = nil) -> String? {
        Decision.analyze(run, map: map, protected: [], spelling: true) { word, _, wantCorrection in
            WordVerdict(known: self.known.contains(Words.normalized(word)), correction: wantCorrection ? suggestion : nil)
        }?.replacement
    }

    func testCapitalsOnPunctuationKeysAreWords() {
        XCTAssertEqual(fix(">kbnm"), "Юлить")
        XCTAssertEqual(fix("\"[jv"), "Эхом")
        XCTAssertEqual(fix("'[jv"), "эхом")
        XCTAssertEqual(fix(">kbnm", apple), "Юлить")
    }

    func testSmartQuotesFromTheFieldAreTheQuoteKeys() {
        XCTAssertEqual(fix("\u{201C}[jv"), "Эхом")
        XCTAssertEqual(fix("\u{2018}[jv"), "эхом")
    }

    func testALastLetterOnAPunctuationKeyIsNotCutOff() {
        XCTAssertEqual(fix("yj;"), "нож", "not \"но;\"")
        XCTAssertEqual(fix("gj."), "пою", "not \"по.\"")
        XCTAssertEqual(fix("k.,k."), "люблю")
    }

    func testOneKnownLetterBeforeAPunctuationKeyIsNoEvidence() {
        XCTAssertEqual(fix("b["), "их")
        XCTAssertEqual(fix("e;"), "уж")
        XCTAssertEqual(fix("'nj"), "это", "a leading quote key is not stripped")
    }

    func testSentencePunctuationFollowsTheLayout() {
        XCTAssertEqual(fix("ghbdtn/"), "привет.", "Russian - PC: \".\" on \"/\"")
        XCTAssertEqual(fix("ghbdtn?"), "привет,", "Russian - PC: \",\" on Shift+/")
        XCTAssertEqual(fix("ghbdtn&", apple), "привет.", "Apple Russian: \".\" on Shift+7")
        XCTAssertEqual(fix("ghbdtn^", apple), "привет,", "Apple Russian: \",\" on Shift+6")
        XCTAssertEqual(fix("ghbdtn!"), "привет!", "the same key in both layouts stays")
        XCTAssertEqual(fix("руддщю"), "hello.")
        XCTAssertEqual(fix("руддщб"), "hello,")
    }

    func testAKnownWordWithPunctuationStaysAsTyped() {
        XCTAssertNil(fix("hello,"))
        XCTAssertNil(fix("no;"))
        XCTAssertNil(fix("привет."))
        XCTAssertNil(fix("#yt"), "a symbol that is no letter key keeps the run out")
    }

    // Issue #2: a quote typed with the current layout's quote key stays a quote ("@" is the US key for the Russian
    // Shift+2), while a key that is punctuation only in the other layout still converts ("&" -> ".").
    func testAQuoteTypedAsAQuoteStays() {
        XCTAssertEqual(fix("\"дуеэы", apple), "\"let's")
        XCTAssertEqual(fix("еуф\"", apple), "tea\"")
        XCTAssertEqual(fix("\u{201C}дуеэы", apple), "\"let's", "a plain quote has a key; the editor smartens it again")
        XCTAssertEqual(fix("еуф\u{201D}", apple), "tea\"")
        XCTAssertEqual(fix("руддщ.", apple), "hello.", "the Russian full stop typed as such")
        XCTAssertNil(fix("@ghbdtn", apple), "a mention stays: \"@\" keeps the run out")
        XCTAssertEqual(fix("ghbdtn&", apple), "привет.")
    }

    func testAKnownWordAfterAQuoteIsNotConverted() {
        XCTAssertNil(fix("\"ну", apple), "not \"ye")
        XCTAssertNil(fix("(hello"))
    }

    // 0.1.6 regression found by review: English abbreviations, initials and list letters became Russian words.
    func testOneLetterWithAStopCommaOrShiftStaysEnglish() {
        for run in ["p.", "y.", "t.", "T.", "c,", "a,", "\"a", "e:"] { XCTAssertNil(fix(run), run) }
    }

    func testAConvertedWordHasARegularCase() {
        XCTAssertNil(fix("rhs:"), "not крыЖ")
        XCTAssertEqual(fix("Ghbdtn"), "Привет")
    }

    func testTheWordAloneWhenTheWholeRunIsNoWord() {
        XCTAssertEqual(fix("ghbdtn,"), "привет,", "the US comma key, as before 0.1.6")
        XCTAssertEqual(fix("ghbdtn."), "привет.")
    }

    func testCodeSpansAndMarkupStayAsTyped() {
        // Apple Russian: the backtick key is "]", so "`rg`" would read as "`кп`" (the real checker does not know "rg").
        XCTAssertNil(fix("`rg`", apple))
        XCTAssertNil(fix("`ghbdtn`", apple))
        XCTAssertNil(fix("ECC**", suggestion: "ETC"), "no typo fix next to markup")
    }

    // Swift review of 0.1.7: cases the first 0.1.7 draft converted although 0.1.5 and 0.1.6 did not.
    func testRussianLettersThatBecomePunctuationGiveNoWord() {
        XCTAssertNil(fix("бэка"), "not \",'rf\"")
    }

    func testAKnownEnglishPieceKeepsTheRun() {
        XCTAssertNil(fix("[the"), "not херу")
        XCTAssertNil(fix(",then"), "not берут")
        XCTAssertEqual(fix("'nj"), "это", "a two-letter piece the checker knows (nj) is no evidence")
        XCTAssertEqual(fix("\"[jv"), "Эхом")
        XCTAssertEqual(fix(";er"), "жук")
    }

    func testLeadingDotBracketOrApostropheBeforeOneLetterStays() {
        for run in [".h", "[b]", "'t"] { XCTAssertNil(fix(run), run) }
        XCTAssertEqual(fix(",s"), "бы")
        XCTAssertEqual(fix(";t"), "же")
    }

    func testPathsAndCommandsStayAsTyped() {
        XCTAssertNil(fix("/gh"))
        XCTAssertNil(fix("~ws"))
    }

    func testCamelCaseFromLetterKeysStillConverts() {
        XCTAssertEqual(fix("шЗрщту"), "iPhone", "only a capital from a Shift punctuation key must fit")
    }

    func testMarkdownStarsAfterAWordConvert() {
        XCTAssertEqual(fix("Вкщшв;;", apple), "Droid**", "Apple Russian Shift+8 is \";\", US \"*\"")
        XCTAssertEqual(fix("руддщ:", apple), "hello:", "a typed colon stays")
    }

    // NSSpellChecker judges the pieces of "k.,k" (two known "k"): such words are known to the lexicon alone.
    func testOnlyPlainWordsGoToTheSystemChecker() {
        for word in ["hello", "don't", "привет"] { XCTAssertTrue(Words.checkable(word), word) }
        for word in ["k.,k", ",s", "'nj", ";er", "'em", "a.b"] { XCTAssertFalse(Words.checkable(word), word) }
    }

    func testSpellingKeepsThePunctuationAsTyped() {
        XCTAssertEqual(fix("helo,", suggestion: "hello"), "hello,")
    }

    func testTheCoreIsWhatIsProtectedAndLearned() {
        XCTAssertEqual(Words.core("ghbdtn?!"), "ghbdtn")
        XCTAssertEqual(Words.core("\u{2018}[jv"), "'[jv")
        XCTAssertEqual(Words.core("hello\u{1F600}"), "hello\u{1F600}", "an emoji is not punctuation")
        var profile = Profile()
        profile.learning = true
        profile.recordUndo("yj;")
        XCTAssertEqual(profile.rejectedWords["yj"], 1)
    }
}
