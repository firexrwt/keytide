import Foundation

public enum Language: String, Codable, CaseIterable { case en, ru }

public struct LayoutMap {
    private let maps: [Language: [Character: Character]]

    public init(englishToRussian: [Character: Character], russianToEnglish: [Character: Character]) {
        maps = [.ru: englishToRussian, .en: russianToEnglish]
    }

    public func convert(_ word: String, to language: Language) -> String? {
        guard let map = maps[language], !word.isEmpty else { return nil }
        var result = String()
        result.reserveCapacity(word.utf8.count)
        for char in word {
            guard let converted = map[char] else { return nil }
            result.append(converted)
        }
        return result
    }

    public static let qwerty = LayoutMap(
        englishToRussian: dictionary("qwertyuiop[]asdfghjkl;'zxcvbnm,./`", "йцукенгшщзхъфывапролджэячсмитьбю.ё"),
        russianToEnglish: dictionary("йцукенгшщзхъфывапролджэячсмитьбюё", "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"))

    private static func dictionary(_ source: String, _ target: String) -> [Character: Character] {
        var map = Dictionary(uniqueKeysWithValues: zip(source, target))
        for (a, b) in zip(source.uppercased(), target.uppercased()) { map[a] = b }
        return map
    }
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
    // Closing punctuation typed right after a word: the word is corrected, the punctuation is kept as typed.
    public static let trailingPunctuation = CharacterSet(charactersIn: ".,!?;:)]}")

    public static func normalized(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }

    public static func language(of word: String) -> Language? {
        guard !word.isEmpty, word.utf16.count <= maximumLength else { return nil }
        var latin = false, russian = false
        for s in word.unicodeScalars {
            switch s.value {
            case 65...90, 97...122: latin = true
            case 0x410...0x44F, 0x401, 0x451: russian = true
            case 39, 44, 46, 47, 59, 91, 93, 96: break
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
    public static func choose(word: String, original: WordVerdict, alternate: String?,
                              alternateVerdict: WordVerdict?, protected: Set<String>,
                              spelling: Bool) -> Correction? {
        guard word.utf16.count >= 2, let source = Words.language(of: word),
              !protected.contains(Words.normalized(word)), !original.known else { return nil }
        let target: Language = source == .en ? .ru : .en
        if let alternate, Words.language(of: alternate) == target, Words.isPlain(alternate),
           alternateVerdict?.known == true || protected.contains(Words.normalized(alternate)) {
            return Correction(original: word, replacement: alternate, language: target, kind: .layout)
        }
        guard spelling, word.utf16.count >= 3, Words.isPlain(word),
              word == word.lowercased() || word == word.uppercased() || word == word.capitalized,
              let suggestion = original.correction,
              Words.language(of: suggestion) == source, Words.isPlain(suggestion),
              Words.oneEditApart(word, suggestion), !protected.contains(Words.normalized(suggestion)) else {
            return nil
        }
        let replacement = Words.applyCase(of: word, to: suggestion)
        return Correction(original: word, replacement: replacement, language: source, kind: .spelling)
    }
}
