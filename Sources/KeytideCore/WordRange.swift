import Foundation

public struct WordRange: Equatable {
    public let word: String
    public let range: NSRange

    public init(word: String, range: NSRange) {
        self.word = word
        self.range = range
    }

    public static func preceding(in prefix: String, offset: Int, requireBoundary: Bool) -> WordRange? {
        let ns = prefix as NSString
        guard ns.length > 0, ns.length <= 160, offset >= 0, offset <= Int.max - ns.length else { return nil }
        var end = ns.length
        if requireBoundary {
            guard let last = UnicodeScalar(ns.character(at: end - 1)),
                  CharacterSet.whitespacesAndNewlines.contains(last) else { return nil }
        }
        while end > 0, let scalar = UnicodeScalar(ns.character(at: end - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) { end -= 1 }
        while end > 0, let scalar = UnicodeScalar(ns.character(at: end - 1)), Words.trailingPunctuation.contains(scalar) { end -= 1 }
        var start = end
        while start > 0, let scalar = UnicodeScalar(ns.character(at: start - 1)),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) { start -= 1 }
        guard start < end, end - start <= Words.maximumLength, start > 0 || offset == 0 else { return nil }
        let range = NSRange(location: start, length: end - start), word = ns.substring(with: range)
        guard Words.language(of: word) != nil else { return nil }
        return WordRange(word: word, range: NSRange(location: offset + start, length: range.length))
    }
}
