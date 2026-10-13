import Foundation

public enum Language: String, Codable, CaseIterable { case en, ru }

public struct LayoutMap {
    private let maps: [Language: [Character: Character]]

    public init(englishToRussian: [Character: Character], russianToEnglish: [Character: Character]) {
        maps = [.ru: englishToRussian, .en: russianToEnglish]
    }

    // The whole typed run, punctuation included: what the same keys give in the other layout. A character missing
    // from the map is the same on both layouts (digits, "!", "(") and stays; the caller validates the result.
    public func convert(_ run: String, to language: Language) -> String? {
        guard let map = maps[language], !run.isEmpty else { return nil }
        var result = String()
        result.reserveCapacity(run.utf8.count)
        for char in run { result.append(map[char] ?? char) }
        return result
    }

    // US and "Russian - PC", plain and Shift: tests only, the app builds its map from the enabled layouts.
    public static let qwerty: LayoutMap = {
        let english = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~@#$^&")
        let russian = Array("йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё\"№;:?")
        let forward = Dictionary(uniqueKeysWithValues: zip(english, russian))
        return LayoutMap(englishToRussian: forward, russianToEnglish: Dictionary(uniqueKeysWithValues: zip(russian, english)))
    }()
}

public struct WordVerdict {
    public let known: Bool
    public let correction: String?
    public init(known: Bool, correction: String? = nil) {
        self.known = known; self.correction = correction
    }
}

public struct Correction: Equatable {
    public enum Kind { case layout, spelling }
    public let original: String
    public let replacement: String
    public let language: Language
    public let kind: Kind
}

public enum Words {
    public static let maximumLength = 64

    public static func normalized(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }

    // A typed run (everything since the last space) as a word and the punctuation after it. Punctuation keys differ
    // between layouts (";" is "ж", Apple Russian puts "." on Shift+7), so this split is only for reading the run as
    // typed: is it a known word, is it protected. A layout correction converts and replaces the whole run.
    public static func split(_ run: String) -> (word: String, trail: String) {
        var end = run.endIndex
        while end > run.startIndex, isTypedPunctuation(run[run.index(before: end)]) { end = run.index(before: end) }
        return (String(run[..<end]), String(run[end...]))
    }

    // The word of a run read as typed, smart quotes undone: the key for protection and learning.
    public static func core(_ run: String) -> String { split(plainQuotes(run)).word }

    // What the keys of either layout type besides letters and digits: ASCII punctuation and symbols, "№", "§", "±".
    // Not emoji or other symbols: a run ending in one is not a word.
    private static func isTypedPunctuation(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        switch scalar.value {
        case 33...47, 58...64, 91...96, 123...126, 0x2116, 167, 177: return true
        default: return false
        }
    }

    // Smart quotes an editor substituted (Notes, TextEdit) for the "'" and "\"" keys, which are э and Э in Russian.
    public static func plainQuotes(_ text: String) -> String {
        guard text.contains(where: { "\u{2018}\u{2019}\u{201C}\u{201D}".contains($0) }) else { return text }
        return String(text.map { "\u{2018}\u{2019}".contains($0) ? "'" : "\u{201C}\u{201D}".contains($0) ? "\"" : $0 })
    }

    // Characters on the keys that carry letters in the other layout (х ъ ж э б ю ё and their capitals on US
    // punctuation keys, "." and "," of Russian - PC on "/") do not decide the language.
    public static func language(of word: String) -> Language? {
        guard !word.isEmpty, word.utf16.count <= maximumLength else { return nil }
        var latin = false, russian = false
        for s in word.unicodeScalars {
            switch s.value {
            case 65...90, 97...122: latin = true
            case 0x410...0x44F, 0x401, 0x451: russian = true
            case 34, 39, 44, 46, 47, 58, 59, 60, 62, 91, 92, 93, 96, 123, 124, 125, 126, 167, 177: break
            default: return nil
            }
        }
        guard latin != russian else { return nil }
        return latin ? .en : .ru
    }

    public static func isPlain(_ word: String) -> Bool {
        guard language(of: word) != nil else { return false }
        return word.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }

    // A layout alternate may be a plain word or an English contraction: the apostrophe key is "э" in the Russian
    // layout, so let's typed there arrives as "дуеэы".
    public static func isCandidate(_ word: String) -> Bool { isPlain(word) || isEnglishContraction(word) }

    // One apostrophe and a common ending only: the macOS checker also accepts stray shapes like "s'd".
    public static func isEnglishContraction(_ word: String) -> Bool {
        let parts = word.lowercased().split(separator: "'", omittingEmptySubsequences: false)
        guard parts.count == 2, let stem = parts.first, let ending = parts.last,
              !stem.isEmpty, stem.unicodeScalars.allSatisfy({ (97...122).contains($0.value) }),
              ["s", "t", "re", "ve", "ll", "d", "m"].contains(ending), stem.count >= 2 || stem == "i" else { return false }
        return ending != "t" || stem.hasSuffix("n")
    }

    public static func applyCase(of original: String, to word: String) -> String {
        if original == original.uppercased() { return word.uppercased() }
        if original == original.capitalized { return word.capitalized }
        return word.lowercased()
    }

    // At most one insertion, deletion, substitution or adjacent transposition. O(n).
    public static func oneEditApart(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(normalized(lhs)), b = Array(normalized(rhs))
        guard abs(a.count - b.count) <= 1, a != b else { return false }
        var i = 0
        while i < min(a.count, b.count), a[i] == b[i] { i += 1 }
        if a.count == b.count {
            if Array(a.dropFirst(i + 1)) == Array(b.dropFirst(i + 1)) { return true }
            return i + 1 < a.count && a[i] == b[i + 1] && a[i + 1] == b[i] &&
                Array(a.dropFirst(i + 2)) == Array(b.dropFirst(i + 2))
        }
        let longer = a.count > b.count ? a : b, shorter = a.count > b.count ? b : a
        return Array(longer.dropFirst(i + 1)) == Array(shorter.dropFirst(i))
    }
}

public enum Decision {
    // The whole decision for one typed run. `verdict(word, language, wantCorrection)` asks the dictionaries: the
    // app passes its cached checker, tests a word list.
    public static func analyze(_ typed: String, map: LayoutMap?, protected: Set<String>, spelling: Bool,
                               verdict: (String, Language, Bool) -> WordVerdict) -> Correction? {
        let run = Words.plainQuotes(typed), word = Words.split(run).word
        guard run.utf16.count >= 2, let language = Words.language(of: word),
              !protected.contains(Words.normalized(word)) else { return nil }
        let original = verdict(word, language, false)
        // One known letter before punctuation keys may still be a word typed in the other layout.
        guard !original.known || word.count < 2 else { return nil }
        let target: Language = language == .en ? .ru : .en
        let alternate = map?.convert(run, to: target)
        let alternateVerdict = alternate.flatMap {
            let converted = Words.split($0).word
            guard Words.isCandidate(converted) else { return nil as WordVerdict? }
            // Profile recognition is request-local: removing a word must take effect without retry.
            return protected.contains(Words.normalized(converted)) ? WordVerdict(known: true) :
                verdict(converted, target, false)
        }
        let detailed = alternateVerdict?.known == true || !spelling || word.utf16.count < 3 ? original :
            verdict(word, language, true)
        return choose(word: run, original: detailed, alternate: alternate, alternateVerdict: alternateVerdict,
                      protected: protected, spelling: spelling)
    }

    // `run`: everything typed since the last space; `original` is the verdict on its word as typed (`Words.split`),
    // `alternate` the whole run converted to the other layout and `alternateVerdict` the verdict on its word.
    // A layout correction replaces the whole run; a spelling correction keeps the punctuation as typed.
    public static func choose(word run: String, original: WordVerdict, alternate: String?,
                              alternateVerdict: WordVerdict?, protected: Set<String>,
                              spelling: Bool) -> Correction? {
        let (word, trail) = Words.split(run)
        // One letter before punctuation keys ("b[" is "их", "e;" is "уж") is no evidence of the typed reading.
        guard run.utf16.count >= 2, let source = Words.language(of: word),
              !protected.contains(Words.normalized(word)), !original.known || word.count < 2 else { return nil }
        let target: Language = source == .en ? .ru : .en
        if let alternate {
            let converted = Words.split(alternate).word
            if converted.utf16.count >= 2, Words.language(of: converted) == target, Words.isCandidate(converted),
               alternateVerdict?.known == true || protected.contains(Words.normalized(converted)) {
                return Correction(original: run, replacement: alternate, language: target, kind: .layout)
            }
        }
        guard spelling, !original.known, word.utf16.count >= 3, Words.isPlain(word),
              word == word.lowercased() || word == word.uppercased() || word == word.capitalized,
              let suggestion = original.correction,
              Words.language(of: suggestion) == source, Words.isPlain(suggestion),
              Words.oneEditApart(word, suggestion), !protected.contains(Words.normalized(suggestion)) else {
            return nil
        }
        let replacement = Words.applyCase(of: word, to: suggestion) + trail
        return Correction(original: run, replacement: replacement, language: source, kind: .spelling)
    }
}
