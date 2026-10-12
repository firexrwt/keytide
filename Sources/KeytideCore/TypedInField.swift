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
        let token = String(String.UnicodeScalarView(text[start...]))
        // An empty run is a word the key stream could not show (after a chord): the field alone names it.
        let run = typed.word + typed.suffix
        guard !token.isEmpty, token.count <= Words.maximumLength, token.hasSuffix(run) else { return .changed }
        return token == run ? .same : .whole(Retype(typed: token))
    }
}
