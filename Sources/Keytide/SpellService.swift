import AppKit
import KeytideCore

final class SpellService {
    private let checker = NSSpellChecker.shared
    private let tag = NSSpellChecker.uniqueSpellDocumentTag()
    private let queue = DispatchQueue(label: "dev.firexrwt.keytide.spelling", qos: .userInitiated)
    private var cache: [String: WordVerdict] = [:]
    private var healthy: Bool?
    private var lexicon: WordLexicon?
    private var workerChecks = 0
    private(set) var busy = false
    private(set) var checks = 0
    private(set) var requests = 0
    private(set) var longestMilliseconds = 0.0
    private(set) var lastMilliseconds = 0.0

    deinit {
        let checker = checker, tag = tag
        queue.async { checker.closeSpellDocument(withTag: tag) }
    }

    func retry() {
        queue.async { [self] in healthy = nil; cache.removeAll(keepingCapacity: true) }
    }

    // Only this serial worker calls the singleton, with an explicit language and no global language changes.
    func analyze(_ word: String, map: LayoutMap?, protected: Set<String>, spelling: Bool,
                 completion: @escaping (Correction?, Bool) -> Void) -> Bool {
        guard !busy, word.utf16.count >= 2, let language = Words.language(of: word),
              !protected.contains(Words.normalized(word)) else { return false }
        busy = true; requests += 1
        queue.async { [self] in
            let start = ProcessInfo.processInfo.systemUptime
            if healthy == nil {
                if lexicon == nil { lexicon = try? WordLexicon.bundled() }
                healthy = lexicon != nil && checker.availableLanguages.contains("ru") && checker.availableLanguages.contains("en") &&
                    isKnown("hello", .en) && isKnown("привет", .ru) &&
                    !isKnown("zzqwxjkk", .en) && !isKnown("ывафывфывфы", .ru)
            }
            var result: Correction?
            if healthy == true {
                let original = verdict(word, language: language, correction: false)
                if !original.known {
                    let alternate = map?.convert(word, to: language == .en ? .ru : .en)
                    let alternateVerdict = alternate.flatMap {
                        guard Words.isCandidate($0) else { return nil as WordVerdict? }
                        // Profile recognition is request-local: removing a word must take effect without retry.
                        return protected.contains(Words.normalized($0)) ? WordVerdict(known: true) :
                            verdict($0, language: language == .en ? .ru : .en, correction: false)
                    }
                    let detailed = alternateVerdict?.known == true || !spelling || word.utf16.count < 3 ? original :
                        verdict(word, language: language, correction: true)
                    result = Decision.choose(word: word, original: detailed, alternate: alternate,
                        alternateVerdict: alternateVerdict, protected: protected, spelling: spelling)
                }
            }
            let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            let available = healthy == true
            let performed = workerChecks
            DispatchQueue.main.async { [self] in
                busy = false
                checks = performed
                lastMilliseconds = milliseconds
                longestMilliseconds = max(longestMilliseconds, milliseconds)
                completion(result, available)
            }
        }
        return true
    }

    private func isKnown(_ word: String, _ language: Language) -> Bool {
        workerChecks += 1
        return checker.checkSpelling(of: word, startingAt: 0, language: language.rawValue, wrap: false,
            inSpellDocumentWithTag: tag, wordCount: nil).location == NSNotFound
    }

    private func verdict(_ word: String, language: Language, correction: Bool) -> WordVerdict {
        let word = Words.normalized(word)
        let key = language.rawValue + (correction ? ":c:" : ":v:") + word
        if let cached = cache[key] { return cached }
        let known = lexicon?.contains(word) == true || isKnown(word, language)
        var suggestion: String?
        if !known && correction && Words.isPlain(word) {
            let range = NSRange(location: 0, length: word.utf16.count)
            let proposed = checker.correction(forWordRange: range, in: word,
                language: language.rawValue, inSpellDocumentWithTag: tag) ??
                checker.guesses(forWordRange: range, in: word, language: language.rawValue,
                    inSpellDocumentWithTag: tag)?.first
            if let candidate = proposed, Words.oneEditApart(word, candidate) {
                suggestion = candidate
            }
        }
        let value = WordVerdict(known: known, correction: suggestion)
        if cache.count >= 1_024 { cache.removeAll(keepingCapacity: true) }
        cache[key] = value
        return value
    }
}
