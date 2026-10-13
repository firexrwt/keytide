// The punctuation at the edges of a run, which may have been typed for either layout, and the evidence a run gives
// for its typed reading. Used by `Decision`.
enum Edges {
    // What a typed quote, bracket, sentence stop or markdown mark stays as when the other layout would give a symbol
    // instead: Shift+2 is a quote on Russian and "@" on US, Apple Russian Shift+7 is "." and US "&". "*" counts
    // (markdown bold) and ";" does not: Apple Russian Shift+8 is ";" and US "*", and Apple Russian has no "*" key,
    // so "**" stays "**" both ways.
    static let natural: Set<Character> = [".", ",", "!", "?", ":", "\"", "'", "(", ")", "-", "`", "*",
                                          "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", "\u{AB}", "\u{BB}"]
    // What 0.1.5 split off as typed: closing sentence punctuation.
    static let sentence: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}"]

    // The run without its closing sentence punctuation, and that punctuation.
    static func sentenceSplit(_ run: String) -> (body: String, sentence: String) {
        var end = run.endIndex
        while end > run.startIndex, sentence.contains(run[run.index(before: end)]) { end = run.index(before: end) }
        return (String(run[..<end]), String(run[end...]))
    }

    // A word as typed blocks a correction when known. One letter is no evidence either way: it converts when the keys
    // around it are letters in the other layout ("b[" is "их", "e;" is "уж", ",s" is "бы", ";t" is "же"), but not
    // after ".", "[" or "'" (".h", "[b]", "'t": file types, markup, contractions), not with "." or "," after it ("p.",
    // "T.", "a, b": abbreviations, initials, lists) and not with a Shift character ("\"a", "e:").
    static func mayConvert(_ run: String, word: String, known: Bool) -> Bool {
        guard word.filter(\.isLetter).count < 2 else { return !known }
        return run.prefix(while: { !$0.isLetter }).allSatisfy { $0 == "," || $0 == ";" } &&
            !Words.split(run).trail.contains(where: { $0 == "." || $0 == "," }) &&
            !run.contains(where: { "\"<>:{}|~".contains($0) })
    }

    // The system checker judges a word with punctuation inside by its pieces, so such a word is unknown as a whole
    // (`Words.checkable`). A piece of three or more letters that is a known word is still evidence of the typed
    // reading ("[the", ",then"). Shorter pieces are not: "k.,k" is "люблю", and the checker accepts two-letter
    // abbreviations like "nj" or "jv" that would block "это" ("'nj") and "Эхом" ("\"[jv").
    static func holdsKnownPiece(_ word: String, original: WordVerdict, known: (String) -> Bool) -> Bool {
        guard !original.known, !Words.checkable(word) else { return false }
        let pieces = word.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 }
        return pieces.contains(where: known)
    }

    // A letter that came from a punctuation key must fit the case of the word: a capital only at the word start or in
    // an all-caps word ("rhs:" is no "крыЖ", ">kbnm" is "Юлить"), a small letter not in an all-caps word ("LF." is no
    // "ДАю"). CamelCase from letter keys ("iPhone") is untouched.
    static func caseFits(typed: String, converted: String) -> Bool {
        let a = Array(typed), b = Array(converted)
        guard a.count == b.count, let first = b.firstIndex(where: \.isLetter) else { return true }
        let fromLetters = a.indices.filter { a[$0].isLetter }.map { b[$0] }
        let shouting = fromLetters.count > 1 && fromLetters.allSatisfy { $0.isUppercase }
        return a.indices.allSatisfy { index in
            guard !a[index].isLetter, b[index].isLetter else { return true }
            return b[index].isUppercase ? index == first || shouting : !shouting
        }
    }

    // The converted run with its edges settled: where both layouts give punctuation, a typed natural character stays
    // over a converted symbol. `typed` has plain quotes: every character of the replacement needs a key, and an
    // editor that smartened the typed quote does it again for the retyped one.
    static func fixed(typed: String, converted: String) -> String {
        let shown = Array(typed)
        var result = Array(converted)
        guard shown.count == result.count else { return converted }
        func settle(_ i: Int) -> Bool {
            guard !shown[i].isLetter, !result[i].isLetter else { return false }
            if natural.contains(shown[i]) && !natural.contains(result[i]) { result[i] = shown[i] }
            return true
        }
        var start = 0
        while start < result.count, settle(start) { start += 1 }
        var end = result.count - 1
        while end > start, settle(end) { end -= 1 }
        return String(result)
    }

    // Leading characters that are punctuation in both layouts: not part of the word as typed. A key that is a letter
    // in the other layout ("'" is "э") stays in the word.
    static func punctuationLead(typed: String, converted: String) -> Int {
        let a = Array(typed), b = Array(converted)
        guard a.count == b.count else { return 0 }
        var count = 0
        while count < a.count, !a[count].isLetter, !a[count].isNumber, !b[count].isLetter, !b[count].isNumber { count += 1 }
        return count
    }

    // The word of a converted run: without the `lead` characters that were punctuation in both layouts and without
    // the punctuation after it. Anything else before the letters means typed letters became punctuation ("бэка" is
    // ",'rf" on US): no word.
    static func word(ofConverted converted: String, lead: Int) -> String {
        let body = Words.split(Words.plainQuotes(converted)).word.dropFirst(lead)
        return body.first?.isLetter == true ? String(body) : ""
    }
}
