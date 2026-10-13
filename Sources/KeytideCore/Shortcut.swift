import Foundation

public struct Modifiers: OptionSet, Codable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Modifiers(rawValue: 1)
    public static let shift = Modifiers(rawValue: 2)
    public static let option = Modifiers(rawValue: 4)
    public static let control = Modifiers(rawValue: 8)
    public static let all = Modifiers(rawValue: 15)
    public var label: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

public struct Shortcut: Codable, Equatable {
    public let keyCode: UInt16?
    public let modifiers: Modifiers
    public let keyLabel: String
    public init(keyCode: UInt16?, modifiers: Modifiers, keyLabel: String = "") {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    public static let undo = Shortcut(keyCode: nil, modifiers: .option)
    public static let protect = Shortcut(keyCode: 2, modifiers: .control, keyLabel: "D")
    public var valid: Bool {
        guard modifiers.rawValue > 0, modifiers.rawValue <= 15, keyLabel.count <= 16,
              !keyLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return false }
        if let keyCode { return keyCode < 128 && !modifiers.intersection([.command, .control, .option]).isEmpty }
        return modifiers.rawValue.nonzeroBitCount == 1
    }
    // A lone modifier shows only its symbol; the app adds the localized "alone".
    public var label: String { modifiers.label + (keyCode == nil ? "" : keyLabel) }
    public func overlaps(_ other: Shortcut) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
}

public struct ModifierTap {
    private var armed: Modifiers?
    private var armedAt: TimeInterval = 0
    public init() {}
    public mutating func interrupt() { armed = nil }
    // `now` and `lastScroll` share one clock. Scrolling is not tapped (every scroll event would pass through Keytide),
    // so a scroll while the modifier was held is looked up once, on release, and disarms it like a key press would.
    public mutating func changed(_ flags: Modifiers, previous: Modifiers, now: TimeInterval = 0,
                                 lastScroll: () -> TimeInterval = { -.infinity }) -> Modifiers? {
        if flags.isEmpty, let armed, previous == armed {
            self.armed = nil
            return lastScroll() < armedAt ? armed : nil
        }
        if previous.isEmpty && flags.rawValue.nonzeroBitCount == 1 { armed = flags; armedAt = now }
        else { armed = nil }
        return nil
    }
}

// The undo shortcut acts only this soon after a correction: a lone Option press much later is more likely a stray
// press than a request to undo a word the user has long accepted. Checked when the shortcut fires, never by a timer.
public enum UndoWindow {
    public static let seconds: TimeInterval = 10
    public static func isOpen(since corrected: TimeInterval, now: TimeInterval) -> Bool {
        now >= corrected && now - corrected <= seconds
    }
    // Keeps running while the Mac sleeps (uptime does not): a correction made before closing the lid is not
    // undoable after waking.
    public static var clock: TimeInterval { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }
}
