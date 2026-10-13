import AppKit
import Carbon
import KeytideCore

// Where the field cannot be read: delete the word the user typed and type the correction as one gated burst.
// The result cannot be read back; instead the burst is refused when anything was pressed after the space,
// when the focus is not a text field, or when a readable field no longer ends with the typed text.
final class KeystrokeCorrector {
    // `lagging`: nothing posted, the field had not caught up with the keys; the caller may try once more.
    enum Outcome { case posted, skipped, lost, lagging }
    private struct Undo {
        // Both whole runs, punctuation included.
        let original: String
        let replacement: String
        let previousSource: String
        let targetSource: String
        let pid: pid_t
        let serial: UInt64
        // A word started after an edit in a field that could not be read may be part of a longer word.
        let learnable: Bool
    }
    private let tap: EventTap
    private let sources: InputSources
    private let text: FocusedText
    private let electron = ElectronAccess()
    private let clipboard: ClipboardProbe
    // Characters before the typed run and its space that the probe copies too: the start of a word the run may end.
    private static let context = 32
    // ponytail: never shrinks; pids of apps that ended stay, and a reused pid is not probed. Fine for a session.
    private var copiesNothing = Set<pid_t>()
    private var undo: Undo?

    init(tap: EventTap, sources: InputSources, text: FocusedText) {
        self.tap = tap; self.sources = sources; self.text = text; clipboard = ClipboardProbe(tap: tap)
    }

    func forget() { undo = nil }

    enum Resolution { case word(Typed), wait(TimeInterval), probe, skip }

    // Electron apps get their accessibility tree as soon as they come to the front, so the first word typed there
    // can already be read.
    func prepare(_ app: NSRunningApplication) { _ = electron.request(for: app, revive: false) }
    func releaseAccessibility(where matches: (String) -> Bool) { electron.release(where: matches) }

    // A `loose` field (a plain AXTextField reports no subrole) gives its whole word too: secure fields are told apart
    // by their subrole and Secure Input, and the burst is refused unless the same element confirms the word twice.

    // Which word the space ended, wherever it stands in the field (`WordChoice` decides, tested in Core). A word typed
    // right after a space is whole as typed (its tail is checked before posting). After an edit (click, caret key,
    // chord, app switch, Backspace past its start) the field names the whole word when it answers; a field that cannot
    // be read gets the typed run, and undoing that teaches nothing.
    // `probe`: a field that does not answer may be read through the clipboard (`readThroughClipboard`).
    func resolve(_ typed: Typed, app: NSRunningApplication, last: Bool, probe: Bool) -> Resolution {
        guard WordChoice.needsField(typed.retype, edited: typed.edited) else { return .word(typed) }
        let answer: WordChoice.Answer, field: AXUIElement?
        switch text.typedInField(typed.retype, pid: app.processIdentifier) {
        case .read(let shown, let element, let loose):
            InputDiagnostics.record("keys field read=\(shown.label) loose=\(loose)")
            answer = .read(shown); field = element
        case .unanswered(let reason):
            InputDiagnostics.record("keys field unanswered reason=\(reason)")
            answer = .unanswered; field = nil
        case .refused(let reason):
            answer = .refused(reason); field = nil
        }
        let requested = answer == .unanswered && electron.request(for: app, revive: true)
        let choice = WordChoice.choose(answer, typed: typed.retype, last: last, treeRequested: requested, probe: probe)
        InputDiagnostics.record("keys word \(choice.label)")
        switch choice {
        case .typed: return .word(typed)
        case .field(let word): return .word(Typed(retype: word, serial: typed.serial, field: field))
        case .again(let delay): return .wait(delay)
        case .probe: return .probe
        case .skip(let reason): InputDiagnostics.record("keys refused reason=\(reason)"); return .skip
        }
    }

    // `word`: read through the clipboard. `typed`: nothing was learned (no key sent, or nothing copied with the caret
    // back in place), so the typed run decides as it did before 0.1.8 - a word is corrected wherever it stands.
    enum ClipboardRead { case word(Typed), typed, skip }

    // The word before the caret of a field that hides its text, copied through the clipboard: enough characters for
    // the typed run, its space and the start of a word it may end (`TypedInField` finds the start). `lost`: the
    // user's keys held meanwhile were dropped. Only to a focus that shows an empty caret (`probeCaret`), and the
    // caret must be back there afterwards; an app that copied nothing is not probed again while it runs.
    func readThroughClipboard(_ typed: Typed, pid: pid_t, completion: @escaping (_ read: ClipboardRead, _ lost: Bool) -> Void) {
        func untouched(_ reason: String) { InputDiagnostics.record("keys clipboard skipped reason=\(reason)"); completion(.typed, false) }
        func refuse(_ reason: String, lost: Bool) { InputDiagnostics.record("keys refused reason=\(reason)"); completion(.skip, lost) }
        guard !copiesNothing.contains(pid) else { return untouched("app copied nothing before") }
        guard case .at(let caret) = text.probeCaret(pid: pid) else { return untouched("no caret") }
        let count = min(Words.maximumLength + 2, typed.retype.run.count + 1 + Self.context)
        let back = { [text] in text.probeCaret(pid: pid) == .at(caret) }
        clipboard.read(count, copyKey: sources.commandKey("c") ?? 8, since: typed.serial, stillThere: back) { [self] result, lost in
            switch result {
            case .refused: completion(.typed, lost)
            case .nothing(let timedOut):
                if timedOut { copiesNothing.insert(pid) }
                // The selection collapsed back where it was, or the Backspaces would land elsewhere.
                guard back() else { return refuse("caret moved", lost: lost) }
                InputDiagnostics.record("keys clipboard gave nothing"); completion(.typed, lost)
            case .copied(let copied):
                guard back() else { return refuse("caret moved", lost: lost) }
                // Longer than the selection: another writer, or a whole line copied without a selection.
                guard copied.utf16.count <= count * 8 else { return refuse("clipboard holds something else", lost: lost) }
                // The copy reaches the field start when it holds everything before the caret (AX counts UTF-16 units).
                let shown = TypedInField.resolve(prefix: copied, fromFieldStart: copied.utf16.count >= caret, typed: typed.retype)
                InputDiagnostics.record("keys clipboard read=\(shown.label)")
                switch WordChoice.fromClipboard(shown, typed: typed.retype) {
                case .field(let word): completion(.word(Typed(retype: word, serial: typed.serial)), lost)
                case .skip(let reason): refuse(reason, lost: lost)
                case .typed, .again, .probe: refuse("clipboard", lost: lost)
                }
            }
        }
    }

    func correct(_ typed: Typed, with replacement: String, source: String, previous: String, pid: pid_t) -> Outcome {
        undo = nil
        let outcome = replace(typed.retype, with: replacement, source: source, since: typed.serial, pid: pid,
                              field: typed.field, previous: previous)
        if outcome == .posted {
            // Our own events never move the serial, so any later key press, even one held during the burst, voids the undo.
            undo = Undo(original: typed.retype.run, replacement: replacement,
                        previousSource: previous, targetSource: source, pid: pid, serial: typed.serial,
                        learnable: !typed.edited)
        }
        return outcome
    }

    var canUndo: Bool { undo.map(eligible) ?? false }

    // Valid only while nothing was pressed since the correction, in the same app and layout.
    func undoLast() -> (original: String, outcome: Outcome, learnable: Bool)? {
        guard let record = undo else { return nil }
        undo = nil
        guard eligible(record) else { InputDiagnostics.record("keys undo refused"); return nil }
        let outcome = replace(Retype(run: record.replacement), with: record.original,
                              source: record.previousSource, since: record.serial, pid: record.pid)
        return (record.original, outcome, record.learnable)
    }

    private func eligible(_ record: Undo) -> Bool {
        tap.serial() == record.serial && sources.currentID == record.targetSource &&
            text.inputOwner()?.processIdentifier == record.pid
    }

    // `field`: the word was read from that element (it may include text typed before), so the element is checked
    // again after the layout switch, right before posting; on refusal the layout goes back to `previous`.
    private func replace(_ retype: Retype, with replacement: String, source: String, since serial: UInt64,
                         pid: pid_t, field: AXUIElement? = nil, previous: String? = nil) -> Outcome {
        let tail = retype.text(retype.run)
        if let reason = text.keystrokeRefusal(expecting: tail, pid: pid, field: field) {
            if reason == FocusedText.lagging { InputDiagnostics.record("keys field behind the keys"); return .lagging }
            return refuse(reason)
        }
        guard let events = events(retype, replacement, source) else { return refuse("no key for a character") }
        guard tap.beginGate(abort: {}, cancel: {}, since: serial) else { return refuse("input after the space") }
        var reason: String?
        if !sources.select(source) {
            reason = "layout switch failed"
        } else if IsSecureEventInputEnabled() || text.inputOwner()?.processIdentifier != pid {
            // The layout switch can take a while: recheck where the events land right before posting.
            reason = "focus moved"
        } else if field != nil, let refusal = text.keystrokeRefusal(expecting: tail, pid: pid, field: field) {
            reason = refusal
            if let previous { _ = sources.select(previous) }
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
