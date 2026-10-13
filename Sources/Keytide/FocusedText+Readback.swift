import AppKit
import ApplicationServices
import Carbon
import KeytideCore

// Readbacks for the field transaction (Coordinator+Field.swift): is the field still in a state the transaction
// expects. Each is one focus check plus at most two short text reads.
extension FocusedText {
    func stillCurrent(_ snapshot: TextSnapshot, caret: NSRange? = nil, word: String? = nil) -> Bool {
        matching(snapshot, states: [(caret ?? snapshot.selection, word ?? snapshot.word.word)]) == 0
    }

    // Only for rollback before anything was posted: may the caret go back where it was (`Rollback.accepts`). The
    // selection and the boundary are read only when the word itself changed.
    func holdsWord(_ snapshot: TextSnapshot) -> Bool {
        guard !IsSecureEventInputEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid,
              let current = focused(), CFEqual(current, snapshot.element),
              let content = text(current, range: snapshot.word.range) else { return false }
        let word = snapshot.word.word, range = snapshot.word.range, caret = snapshot.selection
        if Words.normalized(content) == Words.normalized(word) { return true }
        let end = NSMaxRange(range)
        let selected = selection(current)
        let boundary = caret.location > end ? text(current, range: NSRange(location: end, length: caret.location - end)) : nil
        guard Rollback.accepts(word: word, range: range, caret: caret, shown: content, selected: selected,
                               boundary: boundary) else { return false }
        InputDiagnostics.record("field word rewritten by the editor")
        return true
    }

    // Candidate states share one focus/metadata read; only known short words are compared. Smart quotes the editor
    // put in place of typed ones count as the same text.
    func matching(_ snapshot: TextSnapshot, states: [(caret: NSRange, word: String)], ignoringCase: Bool = false) -> Int? {
        guard !IsSecureEventInputEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid,
              let current = focused(), CFEqual(current, snapshot.element) else {
            InputDiagnostics.record("context changed"); return nil
        }
        guard case .text(let actual) = inspect(current) else { return nil }
        var lastLength = 0
        var content: String?
        for (index, state) in states.enumerated() where actual == state.caret {
            let length = state.word.utf16.count
            if length != lastLength {
                lastLength = length
                content = text(current, range: NSRange(location: snapshot.word.range.location, length: length)).map(Words.plainQuotes)
            }
            let expected = Words.plainQuotes(state.word)
            if let content, ignoringCase ? Words.normalized(content) == Words.normalized(expected) : content == expected {
                return index
            }
        }
        InputDiagnostics.record("field state mismatch")
        return nil
    }
}
