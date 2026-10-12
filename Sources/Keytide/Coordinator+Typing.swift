import AppKit
import KeytideCore

// The keystroke path, for fields outside the AX whitelist: the word comes from the key events or, after an edit,
// from the field when it answers; the replacement is Backspace x N plus the retyped word. Every wait here is a single
// event-triggered retry for one space, never a standing timer.
extension Coordinator {
    func correctTyped(_ typed: Typed, revision: UInt64, owner: pid_t? = nil) {
        guard let app = text.inputOwner() else { InputDiagnostics.record("keys no input app"); return }
        let pid = app.processIdentifier, retry = owner != nil
        // The retry acts only on the app that received the space, while it is still allowed.
        if let owner, owner != pid || !store.profile.enabled ||
            store.profile.excludedApps.contains(app.bundleIdentifier ?? "") {
            InputDiagnostics.record("keys retry refused: app changed"); return
        }
        if !retry { InputDiagnostics.record("keys typed length=\(typed.retype.word.count)") }
        let resolved: Typed
        switch typing.resolve(typed, app: app, last: retry) {
        case .word(let word): resolved = word
        case .skip: return
        case .wait(let delay):
            later(delay, revision: revision) { [weak self] in self?.correctTyped(typed, revision: revision, owner: pid) }
            return
        }
        let started = spell.analyze(resolved.retype.word, map: sources.map, protected: store.immune,
                                    spelling: store.profile.spelling) { [weak self] correction, available in
            guard let self else { return }
            InputDiagnostics.record("keys analyzed available=\(available) correction=\(correction != nil) stale=\(generation != revision)")
            guard available else { onStatus?(tr("status.dictionariesUnavailable")); return }
            guard generation == revision, active == nil else { stale += 1; return }
            guard let correction else { return }
            postTyped(resolved, correction, pid: pid, revision: revision, again: false)
        }
        if !started { InputDiagnostics.record("keys analysis not started") }
    }

    // A field behind the keys (Electron applies them to its accessibility text late) gets one more look before posting.
    private func postTyped(_ typed: Typed, _ correction: Correction, pid: pid_t, revision: UInt64, again: Bool) {
        guard text.inputOwner()?.processIdentifier == pid,
              let previous = sources.currentID, sources.entries.contains(where: { $0.id == previous }),
              let target = correction.kind == .layout ? sources.targetID(correction.language) : previous else {
            InputDiagnostics.record("keys refused reason=app or layout changed"); return
        }
        switch typing.correct(typed, with: correction.replacement, source: target, previous: previous, pid: pid) {
        case .posted:
            corrections += 1; undoRecord = nil
            onStatus?(correction.kind == .layout ? tr("status.layoutFixed") : tr("status.typoFixed"))
        case .skipped: stale += 1
        case .lost: halt(tr("status.halt.lostCorrection"))
        case .lagging:
            guard !again else { stale += 1; InputDiagnostics.record("keys refused reason=field still behind the keys"); return }
            later(0.04, revision: revision) { [weak self] in
                self?.postTyped(typed, correction, pid: pid, revision: revision, again: true)
            }
        }
    }

    private func later(_ delay: TimeInterval, revision: UInt64, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard generation == revision, active == nil else {
                stale += 1; InputDiagnostics.record("keys retry stale: input after the space"); return
            }
            work()
        }
    }

    // Posting inside the tap's synchronous chord callback would let keys typed after the chord overtake the burst,
    // so a chord only decides here and the undo runs on the next main turn, gated and serial-checked.
    func undoTypedLater(then protecting: Bool) -> Bool {
        DispatchQueue.main.async { [weak self] in
            guard let self, let original = undoTyped(), protecting else { return }
            protect(original)
        }
        return true
    }

    func undoTyped() -> String? {
        guard undoRecord == nil, active == nil, let undone = typing.undoLast() else { return nil }
        switch undone.outcome {
        case .posted:
            undos += 1
            if undone.learnable { store.update { $0.recordUndo(undone.original) } }
            else { InputDiagnostics.record("keys undo not learned: word started after an edit") }
            onStatus?(tr("status.restored"))
            return undone.original
        case .skipped, .lagging: return nil
        case .lost: halt(tr("status.halt.lostUndo")); return nil
        }
    }
}
