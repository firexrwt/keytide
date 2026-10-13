// Whether a typed run is corrected, and into what. A run is everything typed since the last space; a layout
// correction converts and replaces all of it, punctuation included, because punctuation keys are letters in the
// other layout ("yj;" is "нож") and sentence punctuation sits on other keys (Apple Russian "." is US "&").
public enum Decision {
    // The whole decision for one run as typed or read from the field. `verdict(word, language, wantCorrection)` asks
    // the dictionaries: the app passes its cached checker, tests a word list.
    public static func analyze(_ typed: String, map: LayoutMap?, protected: Set<String>, spelling: Bool,
                               verdict: (String, Language, Bool) -> WordVerdict) -> Correction? {
        let run = Words.plainQuotes(typed)
        // A run opening with a backtick, a slash or a tilde, or closing with a backtick, is a code span, a command or a
        // path ("`rg`", "/gh", "~/ws", the end of "`a b`"): left as typed. (Russian - PC on an ANSI keyboard has "ё"
        // on the backtick key; words starting or ending with it are the cost.)
        guard run.utf16.count >= 2, !"`/~".contains(run.first!), Edges.sentenceSplit(run).body.last != "`",
              let language = Words.language(of: Words.split(run).word) else {
            return nil
        }
        let target: Language = language == .en ? .ru : .en
        let converted = map?.convert(run, to: target)
        let lead = converted.map { Edges.punctuationLead(typed: run, converted: $0) } ?? 0
        let word = String(Words.split(run).word.dropFirst(lead))
        guard !word.isEmpty, !protected.contains(Words.normalized(word)) else { return nil }
        let original = verdict(word, language, false)
        guard Edges.mayConvert(run, word: word, known: original.known),
              !Edges.holdsKnownPiece(word, original: original, known: { verdict($0, language, false).known }) else {
            return nil
        }
        let alternate = converted.map { Edges.fixed(typed: run, converted: $0) }
        let alternateVerdict = alternate.flatMap {
            let word = Edges.word(ofConverted: $0, lead: lead)
            guard Words.isCandidate(word) else { return nil as WordVerdict? }
            // Profile recognition is request-local: removing a word must take effect without retry.
            return protected.contains(Words.normalized(word)) ? WordVerdict(known: true) : verdict(word, target, false)
        }
        // The checker's suggestions are asked for only where a typo fix may happen (see `choose`).
        let spellable = spelling && lead == 0 && Edges.sentenceSplit(run).body == word && word.utf16.count >= 3
        let detailed = alternateVerdict?.known == true || !spellable ? original : verdict(word, language, true)
        // Layout first, then the word alone, then a typo fix: the order of 0.1.5.
        if let result = choose(run, lead: lead, original: detailed, alternate: alternate,
                               alternateVerdict: alternateVerdict, protected: protected, spelling: false) {
            return result
        }
        // The word alone, its sentence punctuation kept as typed (as before 0.1.6): "ghbdtn," with the US comma key
        // is "привет," although that key is "б" in Russian.
        let (body, sentence) = Edges.sentenceSplit(run)
        if !sentence.isEmpty, body.utf16.count >= 2,
           let alone = analyze(body, map: map, protected: protected, spelling: false, verdict: verdict),
           alone.kind == .layout {
            return Correction(original: run, replacement: alone.replacement + sentence, language: alone.language,
                              kind: .layout)
        }
        return choose(run, lead: lead, original: detailed, alternate: nil, alternateVerdict: nil,
                      protected: protected, spelling: spelling)
    }

    // `original` is the verdict on the run's word as typed, `alternate` the converted run and `alternateVerdict` the
    // verdict on its word. A spelling correction keeps the punctuation around the word as typed.
    public static func choose(word run: String, original: WordVerdict, alternate: String?,
                              alternateVerdict: WordVerdict?, protected: Set<String>,
                              spelling: Bool) -> Correction? {
        choose(run, lead: 0, original: original, alternate: alternate, alternateVerdict: alternateVerdict,
               protected: protected, spelling: spelling)
    }

    // `lead`: how many leading characters of the run are punctuation in both layouts (an opening quote).
    static func choose(_ run: String, lead: Int, original: WordVerdict, alternate: String?,
                       alternateVerdict: WordVerdict?, protected: Set<String>, spelling: Bool) -> Correction? {
        let (body, trail) = Words.split(run)
        let opening = String(body.prefix(lead)), word = String(body.dropFirst(lead))
        guard run.utf16.count >= 2, let source = Words.language(of: word),
              !protected.contains(Words.normalized(word)), Edges.mayConvert(run, word: word, known: original.known) else {
            return nil
        }
        let target: Language = source == .en ? .ru : .en
        if let alternate {
            let converted = Edges.word(ofConverted: alternate, lead: lead)
            if converted.utf16.count >= 2, Words.language(of: converted) == target, Words.isCandidate(converted),
               Edges.caseFits(typed: run, converted: alternate),
               alternateVerdict?.known == true || protected.contains(Words.normalized(converted)) {
                return Correction(original: run, replacement: alternate, language: target, kind: .layout)
            }
        }
        // A typo fix only for a plain word with sentence punctuation after it, as before 0.1.6: not inside code
        // spans, quotes or markup ("`npm`", "ECC**").
        guard spelling, !original.known, opening.isEmpty, Edges.sentenceSplit(run).body == word,
              word.utf16.count >= 3, Words.isPlain(word),
              word == word.lowercased() || word == word.uppercased() || word == word.capitalized,
              let suggestion = original.correction,
              Words.language(of: suggestion) == source, Words.isPlain(suggestion),
              Words.oneEditApart(word, suggestion), !protected.contains(Words.normalized(suggestion)) else {
            return nil
        }
        let replacement = opening + Words.applyCase(of: word, to: suggestion) + trail
        return Correction(original: run, replacement: replacement, language: source, kind: .spelling)
    }
}
