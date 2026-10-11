import XCTest
@testable import KeytideCore

final class WordLexiconTests: XCTestCase {
    func testBundledDictionaryIncludesModernWordsAndInflectedForms() throws {
        let lexicon = try WordLexicon.bundled()
        XCTAssertGreaterThan(lexicon.wordCount, 500_000)
        XCTAssertLessThan(lexicon.byteCount, 8_388_608)
        for word in ["гугл", "Гугл", "ГУГЛ", "гугла", "загуглишь", "яндексе", "дискордом",
                     "раскладка", "раскладками", "автозамену", "разработчиков", "пожалуйста",
                     "ёлка", "елка", "hello", "github", "GitHub", "macbook", "keyboards", "developers"] {
            XCTAssertTrue(lexicon.contains(word), "Missing word: " + word)
        }
        for word in ["ueuk", "ghbdtn", "zzqwxjkk", "ывафывфывфы", "превет", "tеh", "g00gle", "гугл!",
                     "", String(repeating: "a", count: 65)] {
            XCTAssertFalse(lexicon.contains(word), "Unexpected word: " + word)
        }
    }

    func testLayoutRecognitionUsesBundledWordsPreservesCaseAndProtection() throws {
        let lexicon = try WordLexicon.bundled()
        for (input, expected) in [("ueuk", "гугл"), ("Ueuk", "Гугл"), ("UEUK", "ГУГЛ"),
                                  ("zyltrc", "яндекс"), ("lbcrjhl", "дискорд"),
                                  ("hfcrkflrf", "раскладка"), ("fdnjpfvtyf", "автозамена"),
                                  ("пшерги", "github"), ("ehf", "ура"), ("Ehf", "Ура"), ("lf", "да"), ("Lf", "Да")] {
            let language = try XCTUnwrap(Words.language(of: input))
            let alternate = LayoutMap.qwerty.convert(input, to: language == .en ? .ru : .en)
            func choose(_ protected: Set<String>) -> Correction? {
                Decision.choose(word: input, original: WordVerdict(known: lexicon.contains(input)),
                    alternate: alternate, alternateVerdict: alternate.map { WordVerdict(known: lexicon.contains($0)) },
                    protected: protected, spelling: false)
            }
            XCTAssertEqual(choose([])?.replacement, expected, input)
            XCTAssertNil(choose([Words.normalized(input)]))
            XCTAssertEqual(choose([Words.normalized(expected)])?.replacement, expected)
        }
    }

    func testKnownWordsNeverBecomeSpellingOrLayoutCorrections() throws {
        let lexicon = try WordLexicon.bundled()
        for word in ["гугл", "раскладка", "github", "google", "яндекс"] {
            XCTAssertNil(Decision.choose(word: word, original: WordVerdict(known: lexicon.contains(word), correction: "угол"),
                alternate: "hello", alternateVerdict: WordVerdict(known: true), protected: [], spelling: true))
        }
    }

    // Serialized graph for {ab, cb, cd}; shared terminal and suffix nodes must not add ad.
    private var fixture: Data {
        Data(Array("KTLEX001".utf8) + [34, 0, 0, 0, 3, 0, 0, 0,
            128,
            1, 98, 16, 0, 0, 0,
            2, 98, 16, 0, 0, 0, 100, 16, 0, 0, 0,
            2, 97, 17, 0, 0, 0, 99, 23, 0, 0, 0])
    }

    func testGraphDoesNotInventWordsThroughSharedSuffixes() throws {
        let graph = try WordLexicon(data: fixture)
        XCTAssertEqual(graph.wordCount, 3)
        for word in ["ab", "cb", "cd", "AB"] { XCTAssertTrue(graph.contains(word), word) }
        for word in ["ad", "a", "b", "c", "abcd", "db"] { XCTAssertFalse(graph.contains(word), word) }
    }

    func testEveryTruncationIsRejectedWithoutCrashing() {
        for count in 0..<fixture.count {
            XCTAssertThrowsError(try WordLexicon(data: Data(fixture.prefix(count))), "Length \(count)")
        }
    }

    func testMalformedGraphRejectsInvalidLabelsEdgesAndHeaders() {
        let mutations: [(Int, UInt8)] = [(0, 0), (8, 16), (12, 0), (16, 0), (17, 65),
            (18, 0), (19, 17), (19, 18), (19, 255), (29, 98), (34, 128), (36, 18), (42, 97)]
        for (offset, value) in mutations {
            var data = fixture
            data[offset] = value
            XCTAssertThrowsError(try WordLexicon(data: data), "Offset \(offset), value \(value)")
        }
        XCTAssertThrowsError(try WordLexicon(data: Data(repeating: 0, count: 8_388_609)))
    }
}
