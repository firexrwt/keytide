import Foundation

// What a readable field shows before the space the user just typed, against the word rebuilt from the key events.
// The key stream cannot see text that was already there, so the field decides which word the space ended.
public enum TypedInField: Equatable {
    // The field holds exactly the typed run: a whole word, wherever it stands in the text.
    case same
    // The typed run ends a longer word already in the field (typed after a click or Backspace): correct that word.
    case whole(Retype)
    // The field does not end with the typed run (autocorrect, recasing, text replacement) or the word start is not
    // known: nothing is replaced.
    case changed
    // The space has not reached the field yet (Electron updates its text asynchronously): read again shortly.
    case pending

    // `prefix` is the field text right before the caret; `fromFieldStart` says whether it begins at the field start.
    public static func resolve(prefix: String, fromFieldStart: Bool, typed: Retype) -> TypedInField {
        guard let last = prefix.unicodeScalars.last else { return .changed }
        // Contenteditable fields (Chromium, ProseMirror) report a trailing typed space as a no-break space.
        guard last == " " || last == "\u{00A0}" else { return .pending }
        let text = prefix.unicodeScalars.dropLast()
        var start = text.endIndex
        while start > text.startIndex, !CharacterSet.whitespacesAndNewlines.contains(text[text.index(before: start)]) {
            start = text.index(before: start)
        }
        guard start > text.startIndex || fromFieldStart else { return .changed }
        // Editors may have turned the typed "'" and "\"" into smart quotes: the same keys, the same run.
        let token = Words.plainQuotes(String(String.UnicodeScalarView(text[start...])))
        // An empty run is a word the key stream could not show (after a chord): the field alone names it.
        guard !token.isEmpty, token.count <= Words.maximumLength, token.hasSuffix(typed.run) else { return .changed }
        return token == typed.run ? .same : .whole(Retype(run: token))
    }

    // For diagnostics: the case only, never the word.
    public var label: String {
        switch self {
        case .same: return "same"
        case .whole: return "whole"
        case .changed: return "changed"
        case .pending: return "pending"
        }
    }
}

// Which word the keystroke path corrects at a space. Position never decides (owner rule): a word typed after an edit
// is corrected even where the field cannot be read; the field only names the whole word, asks for one more look, or
// vetoes when it shows something else.
public enum WordChoice: Equatable {
    // The run as typed.
    case typed
    // The field's whole word: the same field must confirm it again before posting.
    case field(Retype)
    // Read the field once more after this delay.
    case again(TimeInterval)
    // The field hides its text: read the word before the caret through the clipboard (`ClipboardProbe`).
    case probe
    // Nothing is corrected; the reason is a literal, for diagnostics.
    case skip(String)

    public enum Answer: Equatable { case read(TypedInField), unanswered, refused(String) }

    // A word typed right after a space is whole as typed: the field is not read at all.
    public static func needsField(_ typed: Retype, edited: Bool) -> Bool { edited || typed.run.isEmpty }

    // `last`: no more looks allowed. `treeRequested`: an Electron app was just asked for its accessibility tree.
    // `probe`: a field that does not answer may be read through the clipboard (the owner's setting), after the
    // Electron tree had its chance.
    public static func choose(_ answer: Answer, typed: Retype, last: Bool, treeRequested: Bool,
                              probe: Bool = false) -> WordChoice {
        switch answer {
        case .read(.same): return .field(typed)
        case .read(.whole(let word)): return .field(word)
        case .read(.changed): return .skip("field shows another word")
        case .read(.pending) where !last: return .again(0.04)
        case .unanswered where treeRequested && !last: return .again(0.15)
        case .unanswered where probe: return .probe
        case .refused(let reason): return .skip(reason)
        case .read(.pending), .unanswered: break
        }
        return typed.run.isEmpty ? .skip("no typed word") : .typed
    }

    // A word copied through the clipboard (`ClipboardProbe`). Its keys went in a fixed order, so a copy without the
    // typed space means the field is not what was assumed (an editor ate the space, a foreign copy), never that it
    // lags: no blind correction then.
    public static func fromClipboard(_ shown: TypedInField, typed: Retype) -> WordChoice {
        switch shown {
        case .same: return .field(typed)
        case .whole(let word): return .field(word)
        case .changed: return .skip("field shows another word")
        case .pending: return .skip("clipboard shows no space")
        }
    }

    public var label: String {
        switch self {
        case .typed: return "typed"
        case .field: return "field"
        case .again: return "again"
        case .probe: return "probe"
        case .skip: return "skip"
        }
    }
}
