import AppKit
import Carbon
import KeytideCore

// Where the field cannot be read: delete the word the user typed and type the correction as one gated burst.
// The result cannot be read back; instead the burst is refused when anything was pressed after the space,
// when the focus is not a text field, or when a readable field no longer ends with the typed text.
final class KeystrokeCorrector {
    enum Outcome { case posted, skipped, lost }
    private struct Undo {
        let original: String
        let replacement: String
        let suffix: String
        let previousSource: String
        let targetSource: String
        let pid: pid_t
        let serial: UInt64
    }
    private let tap: EventTap
    private let sources: InputSources
    private let text: FocusedText
    private var undo: Undo?

    init(tap: EventTap, sources: InputSources, text: FocusedText) {
        self.tap = tap; self.sources = sources; self.text = text
    }

    func forget() { undo = nil }

    func correct(_ typed: Typed, with replacement: String, source: String, previous: String, pid: pid_t) -> Outcome {
        undo = nil
        let outcome = replace(typed.retype, with: replacement, source: source, since: typed.serial, pid: pid)
        if outcome == .posted {
            // Our own events never move the serial, so any later key press, even one held during the burst, voids the undo.
            undo = Undo(original: typed.retype.word, replacement: replacement, suffix: typed.retype.suffix,
                        previousSource: previous, targetSource: source, pid: pid, serial: typed.serial)
        }
        return outcome
    }

    var canUndo: Bool { undo.map(eligible) ?? false }

    // Valid only while nothing was pressed since the correction, in the same app and layout.
    func undoLast() -> (original: String, outcome: Outcome)? {
        guard let record = undo else { return nil }
        undo = nil
        guard eligible(record) else { InputDiagnostics.record("keys undo refused"); return nil }
        let outcome = replace(Retype(word: record.replacement, suffix: record.suffix), with: record.original,
                              source: record.previousSource, since: record.serial, pid: record.pid)
        return (record.original, outcome)
    }

    private func eligible(_ record: Undo) -> Bool {
        tap.serial() == record.serial && sources.currentID == record.targetSource &&
            NSWorkspace.shared.frontmostApplication?.processIdentifier == record.pid
    }

    private func replace(_ retype: Retype, with replacement: String, source: String, since serial: UInt64,
                         pid: pid_t) -> Outcome {
        if let reason = text.keystrokeRefusal(expecting: retype.text(retype.word), pid: pid) { return refuse(reason) }
        guard let events = events(retype, replacement, source) else { return refuse("no key for a character") }
        guard tap.beginGate(abort: {}, cancel: {}, since: serial) else { return refuse("input after the space") }
        var reason: String?
        if !sources.select(source) {
            reason = "layout switch failed"
        } else if IsSecureEventInputEnabled() || NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            // The layout switch can take a while: recheck where the events land right before posting.
            reason = "focus moved"
        } else {
            for event in events { event.post(tap: .cgSessionEventTap) }
        }
        guard tap.finishGate() else { InputDiagnostics.record("keys input lost in the gate"); return .lost }
        if let reason { return refuse(reason) }
        InputDiagnostics.record("keys posted deletions=\(retype.deletions)")
        return .posted
    }

    private func refuse(_ reason: String) -> Outcome {
        InputDiagnostics.record("keys refused reason=\(reason)")
        return .skipped
    }

    // Backspaces, then each character with its key in the target layout, then the space. Built before the gate opens.
    private func events(_ retype: Retype, _ replacement: String, _ source: String) -> [CGEvent]? {
        guard let eventSource = CGEventSource(stateID: .privateState) else { return nil }
        var strokes = [(key: UInt16, shift: Bool, text: String)](repeating: (51, false, ""), count: retype.deletions)
        for character in retype.text(replacement) {
            if character == " " { strokes.append((49, false, " ")); continue }
            guard let stroke = sources.stroke(character, source: source) else { return nil }
            strokes.append((stroke.key, stroke.shift, String(character)))
        }
        var events: [CGEvent] = []
        events.reserveCapacity(strokes.count * 2)
        for stroke in strokes {
            let units = Array(stroke.text.utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: stroke.key, keyDown: down) else { return nil }
                event.flags = stroke.shift ? [.maskShift, .maskNonCoalesced] : [.maskNonCoalesced]
                event.setIntegerValueField(.eventSourceUserData, value: EventTap.marker)
                if !units.isEmpty { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units) }
                events.append(event)
            }
        }
        return events
    }
}
