import XCTest
@testable import KeytideCore

// A typo fix is a slip of the finger (owner decision 2026-11-04): a neighbouring key instead of the right one, a
// neighbouring or the same key pressed with it, a key missed, or two keys swapped. Not any word one letter away.
final class KeyGridTests: XCTestCase {
    private func adjacent(_ a: Character, _ b: Character) -> Bool {
        KeyGrid.adjacent(LayoutMap.qwerty.keys[.en]![a]!, LayoutMap.qwerty.keys[.en]![b]!)
    }

    func testNeighboursFollowTheRowsAndTheirStagger() {
        for (a, b) in [("q", "w"), ("q", "a"), ("w", "a"), ("w", "s"), ("a", "z"), ("s", "z"), ("d", "c"), ("g", "b"),
                       ("p", "["), ("l", ";"), ("m", ","), ("o", "p")] as [(Character, Character)] {
            XCTAssertTrue(adjacent(a, b), "\(a)\(b)")
            XCTAssertTrue(adjacent(b, a), "\(b)\(a)")
        }
        for (a, b) in [("q", "s"), ("t", "b"), ("a", "a"), ("a", "x"), ("e", "u"), ("a", "o"), ("q", "z")]
            as [(Character, Character)] {
            XCTAssertFalse(adjacent(a, b), "\(a)\(b)")
        }
        XCTAssertEqual(KeyGrid.qwertyOrder.count, 34)
    }

    func testEnglishSlips() {
        let map = LayoutMap.qwerty
        for (typed, intended) in [("hwllo", "hello"), ("cst", "cat"), ("HWLLO", "hello"), ("Hwllo", "hello"),
                                  ("hrello", "hello"), ("jhello", "hello"), ("hgello", "hello"), ("hellop", "hello"),
                                  ("helllo", "hello"), ("hhello", "hello"),
                                  ("helloo", "hello"), ("teh", "the"), ("helo", "hello"), ("helo", "help")] {
            XCTAssertTrue(map.slip(typed, from: intended, in: .en), "\(typed) -> \(intended)")
        }
        for (typed, intended) in [("cat", "cut"), ("hpllo", "hello"), ("hpello", "hello"), ("cat", "dog"),
                                  ("hello", "hello"), ("hwlo", "hello"), ("helloz", "hello")] {
            XCTAssertFalse(map.slip(typed, from: intended, in: .en), "\(typed) -> \(intended)")
        }
    }

    func testRussianSlipsIncludingLettersOnPunctuationKeys() {
        let map = LayoutMap.qwerty
        for (typed, intended) in [("приыет", "привет"), ("пртвет", "привет"), ("спасибл", "спасибо"),
                                  ("кошкп", "кошка"), ("хорощо", "хорошо"), ("дук", "жук"), ("прмвет", "привет")] {
            XCTAssertTrue(map.slip(typed, from: intended, in: .ru), "\(typed) -> \(intended)")
        }
        // Spelling mistakes, not slips: е and и, а and о sit far apart.
        for (typed, intended) in [("превет", "привет"), ("малоко", "молоко")] {
            XCTAssertFalse(map.slip(typed, from: intended, in: .ru), "\(typed) -> \(intended)")
        }
    }

    // ISO (this owner's MacBook): "\" (42, Apple Russian "ё") ends the home row next to "'" ("э"), "§" (10) is the
    // top-left key, "`" (50) sits left of Z. Letter keys do not move.
    func testISOMovesTheThreeKeysOnly() {
        XCTAssertTrue(KeyGrid.adjacent(42, 39, iso: true))
        XCTAssertTrue(KeyGrid.adjacent(42, 30, iso: true))
        XCTAssertFalse(KeyGrid.adjacent(42, 39))
        XCTAssertTrue(KeyGrid.adjacent(42, 30))
        XCTAssertTrue(KeyGrid.adjacent(50, 6, iso: true), "` next to z")
        XCTAssertTrue(KeyGrid.adjacent(50, 0, iso: true), "` next to a")
        XCTAssertFalse(KeyGrid.adjacent(50, 6))
        XCTAssertTrue(KeyGrid.adjacent(10, 18, iso: true), "§ next to 1")
        XCTAssertFalse(KeyGrid.adjacent(10, 18), "no § key on ANSI")
        for (a, b) in [(12, 13), (12, 0), (13, 0), (2, 8), (5, 11)] as [(UInt16, UInt16)] {
            XCTAssertEqual(KeyGrid.adjacent(a, b, iso: true), KeyGrid.adjacent(a, b), "\(a) \(b)")
        }
        var apple = LayoutMap(englishToRussian: [:], russianToEnglish: [:],
                              keys: [.ru: LayoutMap.qwerty.keys[.ru]!.merging(["ё": 42]) { $1 }])
        XCTAssertFalse(apple.slip("ещэ", from: "ещё", in: .ru))
        apple.isoKeyboard = true
        XCTAssertTrue(apple.slip("ещэ", from: "ещё", in: .ru))
    }

    func testNoKnownKeysIsNoSlip() {
        XCTAssertFalse(LayoutMap(englishToRussian: [:], russianToEnglish: [:]).slip("hwllo", from: "hello", in: .en))
        XCTAssertFalse(LayoutMap.qwerty.slip("hwllo", from: "hello", in: .ru))
    }

    private func fix(_ run: String, suggestion: String, map: LayoutMap? = .qwerty) -> String? {
        Decision.analyze(run, map: map, protected: [], spelling: true) { word, _, wantCorrection in
            WordVerdict(known: Words.normalized(word) == suggestion, correction: wantCorrection ? suggestion : nil)
        }?.replacement
    }

    func testDecisionFixesOnlySlips() {
        XCTAssertEqual(fix("приыет", suggestion: "привет"), "привет")
        XCTAssertEqual(fix("Hwllo,", suggestion: "hello"), "Hello,")
        XCTAssertNil(fix("превет", suggestion: "привет"), "the checker's guess is no slip")
        XCTAssertNil(fix("cut", suggestion: "cat"))
        XCTAssertNil(fix("приыет", suggestion: "привет", map: nil), "no layouts, no keys, no typo fix")
    }
}
