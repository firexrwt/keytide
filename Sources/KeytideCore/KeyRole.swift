// What a key press means for the word before the caret, before any field is read. Virtual key codes are the same
// on every layout.
public enum KeyRole: Equatable {
    // Space, Return or keypad Enter: the word before it may be corrected.
    case boundary
    // A chord, or a key that moves the caret or edits around it: a field correction can no longer be undone.
    case edit
    // Anything else, including a held key repeating.
    case typing

    // Tab, Delete, Escape, Home, Page Up, Forward Delete, End, Page Down and the four arrows.
    static let editing: Set<UInt16> = [48, 51, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126]
    // Space, Return, keypad Enter.
    static let boundaries: Set<UInt16> = [49, 36, 76]

    public static func of(_ code: UInt16, flags: Modifiers, repeated: Bool) -> KeyRole {
        if !flags.intersection([.command, .control, .option]).isEmpty || editing.contains(code) { return .edit }
        return !repeated && boundaries.contains(code) ? .boundary : .typing
    }
}
