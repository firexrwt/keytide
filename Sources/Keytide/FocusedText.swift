import AppKit
import ApplicationServices
import Carbon
import KeytideCore

struct TextSnapshot {
    let element: AXUIElement
    let pid: pid_t
    let selection: NSRange
    let word: WordRange
}

enum Capture {
    case field(TextSnapshot)
    // Nothing verified about the field; the keystroke path may still act.
    case unreadable(String)
    // Nothing may touch this input.
    case blocked(String)
}

final class FocusedText {
    // Candidate compatibility scope. Extending it requires real text and secure-field checks.
    static let compatibleApps: Set<String> = ["com.apple.TextEdit", "com.apple.Safari", "com.google.Chrome",
        "net.imput.helium", "com.openai.codex"]
    private let system = AXUIElementCreateSystemWide()
    private(set) var calls = 0

    init() { AXUIElementSetMessagingTimeout(system, 0.012) }

    func capture(boundary: Bool, exclusions: [String]) -> Capture {
        InputDiagnostics.record("capture app=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none") trusted=\(AXIsProcessTrusted()) secure=\(IsSecureEventInputEnabled())")
        guard AXIsProcessTrusted() else { return .blocked("untrusted") }
        guard !IsSecureEventInputEnabled() else { return .blocked("secure input") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let id = app.bundleIdentifier, !exclusions.contains(id) else { return .blocked("app") }
        guard Self.compatibleApps.contains(id) else { return .unreadable("app") }
        guard let element = focused() else { return .unreadable("focus") }
        let selection: NSRange
        switch inspect(element) {
        case .silent: return .unreadable("ax error")
        case .secure: return .blocked("secure field")
        case .unknown(let range):
            if boundary, let range, range.length > 0 { return .blocked("selection") }
            return .unreadable("role")
        case .text(let range): selection = range
        }
        var pid: pid_t = 0
        // Focus inside another process (a non-activating panel): the burst would land there.
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else { return .blocked("pid") }
        AXUIElementSetMessagingTimeout(element, 0.012)
        let word: WordRange
        if selection.length > 0 {
            guard !boundary else { return .blocked("selection") }
            guard selection.length <= Words.maximumLength, let text = text(element, range: selection),
                  Words.language(of: text) != nil else { return .unreadable("selected text") }
            word = WordRange(word: text, range: selection)
        } else {
            let offset = max(0, selection.location - 160)
            guard let prefix = text(element, range: NSRange(location: offset, length: selection.location - offset)),
                  let found = WordRange.preceding(in: prefix, offset: offset, requireBoundary: boundary) else {
                return .unreadable("word")
            }
            word = found
        }
        return .field(TextSnapshot(element: element, pid: pid, selection: selection, word: word))
    }

    // One read before a keystroke replacement, nil when allowed. AX silence allows it (Electron); a secure field,
    // another process, a non-text focus, a selection or a readable field that no longer ends with `tail` refuses it.
    func keystrokeRefusal(expecting tail: String?, pid: pid_t) -> String? {
        guard !IsSecureEventInputEnabled() else { return "secure input" }
        guard let element = focused() else { InputDiagnostics.record("keys focus unreadable"); return nil }
        var owner: pid_t = 0
        if AXUIElementGetPid(element, &owner) == .success, owner != pid { return "focus in another process" }
        // Once per correction, not per key: a busy browser may need longer than the 12 ms default.
        AXUIElementSetMessagingTimeout(element, 0.05)
        switch inspect(element) {
        case .silent: InputDiagnostics.record("keys field unreadable"); return nil
        case .secure: return "secure field"
        case .unknown(nil): return "focus is not text"
        case .unknown(let range?): return range.length == 0 ? nil : "selection"
        case .text(let range):
            guard range.length == 0 else { return "selection" }
            // macOS autocorrect or a text replacement may have rewritten the word on the same space.
            guard let tail, range.location >= tail.utf16.count, let actual = text(element,
                  range: NSRange(location: range.location - tail.utf16.count, length: tail.utf16.count)) else { return nil }
            return actual == tail ? nil : "text changed"
        }
    }

    func stillCurrent(_ snapshot: TextSnapshot, caret: NSRange? = nil, word: String? = nil) -> Bool {
        matching(snapshot, states: [(caret ?? snapshot.selection, word ?? snapshot.word.word)]) == 0
    }

    // Same field and the word still at its range, ignoring case: the editor may recase it while a transaction is
    // open (TextEdit capitalizes a document's first word). Only for rollback before anything was posted.
    func holdsWord(_ snapshot: TextSnapshot) -> Bool {
        guard !IsSecureEventInputEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid,
              let current = focused(), CFEqual(current, snapshot.element),
              let content = text(current, range: snapshot.word.range) else { return false }
        return Words.normalized(content) == Words.normalized(snapshot.word.word)
    }

    // Candidate states share one focus/metadata read; only known short words are compared.
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
                content = text(current, range: NSRange(location: snapshot.word.range.location, length: length))
            }
            if let content, ignoringCase ? Words.normalized(content) == Words.normalized(state.word) : content == state.word {
                return index
            }
        }
        InputDiagnostics.record("field state mismatch selection=\(actual)")
        return nil
    }

    func selection(_ element: AXUIElement) -> NSRange? {
        guard let object = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        return Self.range(object)
    }

    private static func range(_ object: CFTypeRef) -> NSRange? {
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(object, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range),
              range.location >= 0, range.length >= 0, range.location <= 10_000_000,
              range.length <= 10_000_000 - range.location else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    func setSelection(_ element: AXUIElement, _ range: NSRange) -> Bool {
        guard range.location >= 0, range.length >= 0 else { return false }
        var cf = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cf) else { return false }
        calls += 1
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    func text(_ element: AXUIElement, range: NSRange) -> String? {
        guard range.location >= 0, range.length > 0, range.length <= 160 else { return nil }
        var cf = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cf) else { return nil }
        var output: CFTypeRef?
        calls += 1
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
            value, &output) == .success, let string = output as? String, string.utf16.count == range.length else { return nil }
        return string
    }

    private func focused() -> AXUIElement? {
        guard let object = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(object, to: AXUIElement.self)
    }

    // `silent`: AX did not answer. `unknown(nil)`: AX answered and the focus has no text range, so it is not text.
    private enum Field { case text(NSRange), secure, unknown(NSRange?), silent }

    private func inspect(_ element: AXUIElement) -> Field {
        let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXSelectedTextRangeAttribute] as CFArray
        var result: CFArray?
        calls += 1
        let error = AXUIElementCopyMultipleAttributeValues(element, names, [], &result)
        guard error == .success, let values = result as? [AnyObject], values.count == 3 else {
            InputDiagnostics.record("AX attributes error=\(error.rawValue)"); return .silent
        }
        let range = Self.range(values[2])
        let subrole = values[1] as? String
        if subrole == kAXSecureTextFieldSubrole as String { return .secure }
        guard let role = values[0] as? String, [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(role),
              let range else { return .unknown(range) }
        if let subrole {
            InputDiagnostics.record("AX role=\(role) subrole=\(subrole)")
            guard subrole == kAXSearchFieldSubrole as String || (role == kAXTextAreaRole as String && subrole.isEmpty) else {
                return .unknown(range)
            }
        } else if role != kAXTextAreaRole as String || !Self.missing(values[1]) {
            return .unknown(range)
        }
        return .text(range)
    }

    // Only an explicitly unsupported or empty subrole counts as missing.
    private static func missing(_ value: AnyObject) -> Bool {
        if CFGetTypeID(value) == CFNullGetTypeID() { return true }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        let value = unsafeBitCast(value, to: AXValue.self)
        var error = AXError.success
        return AXValueGetType(value) == .axError && AXValueGetValue(value, .axError, &error) &&
            (error == .attributeUnsupported || error == .noValue)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var output: CFTypeRef?
        calls += 1
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &output)
        if result != .success { InputDiagnostics.record("AX attribute=\(name) error=\(result.rawValue)") }
        return result == .success ? output : nil
    }
}
