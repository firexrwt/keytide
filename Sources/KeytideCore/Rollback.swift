import Foundation

// Whether a field transaction that posted nothing may put the caret back where it was. The editor may have changed
// the word meanwhile: recased it (TextEdit capitalizes a document's first word) or rewritten it (macOS autocorrect).
public enum Rollback {
    // `shown`: the text now at the word's range; `selected`: the field's selection now; `boundary`: the text now
    // between the word and the caret at capture (nil when it was not read).
    public static func accepts(word: String, range: NSRange, caret: NSRange, shown: String, selected: NSRange?,
                               boundary: String?) -> Bool {
        if Words.normalized(Words.plainQuotes(shown)) == Words.normalized(Words.plainQuotes(word)) { return true }
        // A rewrite of the same length, still followed by the typed boundary. A longer or shorter one shifts the text:
        // the range then ends inside a word or holds the space. Text inserted or removed before the word, or one word
        // expanded into several, moves the editor's selection with it: only Keytide's own selection, the caret right
        // after the word or the caret put back count.
        let end = NSMaxRange(range)
        guard caret.location > end, !shown.contains(where: \.isWhitespace), let selected,
              selected == range || selected == NSRange(location: end, length: 0) || selected == caret,
              let boundary, boundary.utf16.count == caret.location - end,
              boundary.allSatisfy(\.isWhitespace) else { return false }
        return true
    }
}
