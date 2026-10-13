import Foundation

// The word being typed, rebuilt from key events where the field cannot be read. Only the current word, never history.
public struct TypedWord {
    private var characters: [Character] = []
    private var known = true
    // The word started where the key stream did not see the text before it: after a click, a caret key or a
    // Backspace past its start. It may be the end of a longer word, so it is only safe where the field can be read.
    private var edited = false
    public private(set) var finishedAfterEdit = false
    // The finished word had characters the key stream could not read: only a readable field can name it.
    public private(set) var finishedUnknown = false

    public init() {}

    public var current: String? { known && !characters.isEmpty ? String(characters) : nil }

    // One key press, in the order the focused app receives it. `text` is nil when the key's characters could not
    // be read. Returns the finished word on a plain space.
    public mutating func key(_ code: UInt16, _ modifiers: Modifiers, text: @autoclosure () -> String?) -> Retype? {
        // Chords (paste, undo, select all, Cmd+Space) change the text in ways the key stream cannot show: the next
        // characters start a new run, marked as an edit.
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { relocate(); return nil }
        switch code {
        case 49: return finish()
        case 36, 76: restart()
        case 51: deleteBackward()
        default:
            if let text = text() { append(text) } else { invalidate() }
        }
        return nil
    }

    // Only characters typed since the word start are ever deleted later, so starting over is always safe; only text
    // the key stream cannot show (chords, dropped input, unreadable keys) makes the word unknown.
    // A key without characters (fn / Globe switching the layout) leaves the word as is. A typed space or Tab starts a
    // clean word; arrows, Home/End, Escape and forward Delete move the caret or change the field (an edit).
    public mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        guard text.allSatisfy({ Self.accepts($0) }) else {
            if text.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { restart() } else { relocate() }
            return
        }
        guard known else { return }
        guard characters.count + text.count <= Words.maximumLength else { invalidate(); return }
        characters.append(contentsOf: text)
    }

    // Deleting past the word start removes older text that later Backspaces never reach: an edit.
    public mutating func deleteBackward() {
        if !characters.isEmpty { if known { characters.removeLast() } } else { edited = true }
    }

    public mutating func invalidate() { known = false; characters.removeAll(keepingCapacity: true) }
    public mutating func restart() { known = true; edited = false; characters.removeAll(keepingCapacity: true) }
    // The caret may now be anywhere in existing text (click, caret keys).
    public mutating func relocate() { restart(); edited = true }

    public mutating func finish() -> Retype? {
        finishedAfterEdit = edited
        finishedUnknown = !known
        defer { restart() }
        guard let typed = current else { return nil }
        return Retype(run: typed)
    }

    // Arrows and function keys report Private Use characters; Tab, Escape and Delete report controls.
    static func accepts(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) &&
                !(0xE000...0xF8FF).contains($0.value)
        }
    }
}

// Everything typed since the last space, punctuation included: the keystroke path replaces exactly this run, since
// punctuation keys mean other characters in the other layout ("yj;" is "нож", not "но;").
public struct Retype: Equatable {
    public let run: String

    public init(run: String) { self.run = run }

    // Backspaces for the typed characters plus the boundary space the app already received.
    public var deletions: Int { run.count + 1 }
    public func text(_ replacement: String) -> String { replacement + " " }
}
