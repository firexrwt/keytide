import AppKit
import ApplicationServices
import KeytideCore

// The field path, for whitelisted apps whose field reads as text: the word is read from the field and replaced in a
// verified transaction (select, insert, confirm), undone the same way.
extension Coordinator {
    func correctField(_ snapshot: TextSnapshot, revision: UInt64) {
        InputDiagnostics.record("captured word")
        _ = spell.analyze(snapshot.word.word, map: sources.map, protected: store.immune,
                          spelling: store.profile.spelling) { [weak self] correction, available in
            guard let self else { return }
            InputDiagnostics.record("analyzed available=\(available) correction=\(correction != nil) stale=\(generation != revision)")
            guard available else { onStatus?(tr("status.dictionariesUnavailable")); return }
            guard generation == revision, active == nil else { stale += 1; return }
            guard let correction, let previous = sources.currentID,
                  sources.entries.contains(where: { $0.id == previous }),
                  let target = correction.kind == .layout ? sources.targetID(correction.language) : previous else { return }
            guard let currentWord = text.text(snapshot.element, range: snapshot.word.range),
                  Words.normalized(currentWord) == Words.normalized(snapshot.word.word) else { stale += 1; return }
            let current = TextSnapshot(element: snapshot.element, pid: snapshot.pid, selection: snapshot.selection,
                word: WordRange(word: currentWord, range: snapshot.word.range))
            let replacement = currentWord == snapshot.word.word ? correction.replacement :
                Words.applyCase(of: currentWord, to: correction.replacement)
            replace(current, with: replacement, source: target, previous: previous) { [weak self] ok in
                guard let self, ok else { return }
                corrections += 1; correctedAt = UndoWindow.clock
                undoRecord = UndoRecord(snapshot: current, replacement: replacement,
                                        previousSource: previous, targetSource: target)
                typing.forget()
                onStatus?(correction.kind == .layout ? tr("status.layoutFixed") : tr("status.typoFixed"))
            }
        }
    }

    @discardableResult func undoLast(after: (() -> Void)? = nil) -> Bool {
        if undoRecord == nil { return active == nil && typing.canUndo && undoTypedLater(then: false) }
        guard let record = undoRecord, active == nil, sources.currentID == record.targetSource,
              let current = text.selection(record.snapshot.element), current.length == 0,
              current.location >= record.snapshot.word.range.location + record.replacement.utf16.count,
              text.stillCurrent(record.snapshot, caret: current, word: record.replacement) else { return false }
        let snapshot = TextSnapshot(element: record.snapshot.element, pid: record.snapshot.pid, selection: current,
            word: WordRange(word: record.replacement, range: NSRange(location: record.snapshot.word.range.location,
                length: record.replacement.utf16.count)))
        replace(snapshot, with: record.snapshot.word.word, source: record.previousSource, previous: record.targetSource) { [weak self] ok in
            guard let self, ok else { return }
            undoRecord = nil
            undos += 1
            store.update { $0.recordUndo(record.snapshot.word.word) }
            onStatus?(tr("status.restored"))
            after?()
        }
        return true
    }

    private func replace(_ snapshot: TextSnapshot, with replacement: String, source: String, previous: String,
                         completion: @escaping (Bool) -> Void) {
        guard active == nil, text.stillCurrent(snapshot), sources.currentID == previous,
              let keys = sources.keystrokes(replacement, source: source),
              let key = keys.first,
              let eventSource = CGEventSource(stateID: .privateState) else {
            InputDiagnostics.record("replace preflight rejected"); completion(false); return
        }
        var events: [CGEvent] = []
        let units = Array(replacement.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key.key, keyDown: down) else {
                completion(false); return
            }
            event.flags = key.shift ? [.maskShift, .maskNonCoalesced] : [.maskNonCoalesced]
            event.setIntegerValueField(.eventSourceUserData, value: EventTap.marker)
            units.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
            }
            var readback = [UniChar](repeating: 0, count: units.count), length = 0
            event.keyboardGetUnicodeString(maxStringLength: readback.count, actualStringLength: &length, unicodeString: &readback)
            guard length == units.count, readback == units else { completion(false); return }
            events.append(event)
        }
        InputDiagnostics.record("replace started")
        let token = UUID()
        active = token
        let started = ProcessInfo.processInfo.systemUptime
        let insertedCaret = NSRange(location: snapshot.word.range.location + replacement.utf16.count, length: 0)
        let finalCaret = NSRange(location: snapshot.selection.location + replacement.utf16.count - snapshot.word.range.length, length: 0)
        let selectedStates = [(snapshot.word.range, snapshot.word.word), (snapshot.selection, snapshot.word.word)]
        let insertedStates = [(insertedCaret, replacement), (snapshot.word.range, snapshot.word.word),
                              (snapshot.word.range, replacement)]
        let confirmedStates = [(finalCaret, replacement), (insertedCaret, replacement)]
        let restoredStates = [(snapshot.selection, snapshot.word.word), (snapshot.word.range, snapshot.word.word)]
        let transaction = InputTransaction(perform: { [self] step in
            guard active == token else { return .rejected }
            var result = InputTransaction.Check.rejected
            switch step {
            case .prepare:
                // TIS changes can collapse selection. Select the word afterwards.
                if tap.withinGate && sources.select(source) && tap.withinGate &&
                    text.stillCurrent(snapshot) && tap.withinGate && text.setSelection(snapshot.element, snapshot.word.range) {
                    result = .ready
                }
            case .selected:
                if tap.withinGate, sources.currentID == source,
                   let state = text.matching(snapshot, states: selectedStates), tap.hasTime(InputTransaction.postingReserve) {
                    result = state == 0 ? .ready : .waiting
                }
            case .inserted:
                if tap.withinGate, sources.currentID == source,
                   let state = text.matching(snapshot, states: insertedStates), tap.withinGate {
                    if state != 0 { result = .waiting }
                    else if text.setSelection(snapshot.element, finalCaret) { result = .ready }
                }
            case .confirmed:
                if sources.currentID == source, let state = text.matching(snapshot, states: confirmedStates) {
                    if state == 0 { result = .ready }
                    else if tap.withinGate { result = .waiting }
                }
            case .restore:
                // Runs only before posting. The editor may have recased the word or moved the caret meanwhile
                // (TextEdit capitalizes a document's first word); user input is held, so put the caret back.
                if (sources.currentID == source || sources.currentID == previous) && text.holdsWord(snapshot) &&
                    text.setSelection(snapshot.element, snapshot.selection) && sources.select(previous) { result = .ready }
            case .restored:
                if sources.currentID == previous,
                   let state = text.matching(snapshot, states: restoredStates, ignoringCase: true) {
                    if state == 0 { result = .ready }
                    else if tap.withinGate { result = .waiting }
                }
            }
            InputDiagnostics.record("replace step=\(step) result=\(result) elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))")
            return result
        }, post: {
            InputDiagnostics.record("selection confirmed, posting replacement")
            for event in events { event.postToPid(snapshot.pid) }
        }, later: { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + InputTransaction.handoff, execute: work)
        }, completion: { [self] outcome in
            guard active == token else { return }
            active = nil
            let outcome = tap.finishGate(replay: outcome != .uncertain) ? outcome : .uncertain
            InputDiagnostics.record("replace outcome=\(outcome) elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))")
            switch outcome {
            case .confirmed: break
            case .restored: onStatus?(tr("status.skipped"))
            case .uncertain:
                halt(tr("status.halt.uncertain"))
            }
            completion(outcome == .confirmed)
        })
        tap.beginGate(abort: transaction.expire, cancel: transaction.cancel)
        transaction.start()
    }
}
