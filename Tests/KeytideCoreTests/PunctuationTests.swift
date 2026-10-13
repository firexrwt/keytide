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
                                      "люблю", "бы", "no", "let's", "уж", "e"]

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
