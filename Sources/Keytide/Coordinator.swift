import AppKit
import ApplicationServices
import KeytideCore

final class Coordinator {
    let store: ProfileStore
    let sources = InputSources()
    let spell = SpellService()
    let tap = EventTap()
    let text = FocusedText()
    var onStatus: ((String) -> Void)?
    // Internal, not private: the keystroke path lives in Coordinator+Typing.swift.
    var corrections = 0
    var undos = 0
    var stale = 0
    var generation: UInt64 = 0
    var active: UUID?
    var undoRecord: UndoRecord?
    private var waitingForAccess = false
    private var stoppedForFailure = false
    // An Electron app came to the front: its accessibility tree is asked for at the first key typed there.
    private var preparePending = false
    // Lazy: needs tap, sources and text; named apart from the local `keys` in `replace`.
    lazy var typing = KeystrokeCorrector(tap: tap, sources: sources, text: text)

    struct UndoRecord {
        let snapshot: TextSnapshot
        let replacement: String
        let previousSource: String
        let targetSource: String
    }

    init(store: ProfileStore) {
        self.store = store
        tap.onKey = { [weak self] code, flags, repeated, typed in self?.key(code, flags, repeated, typed) ?? false }
        tap.onModifier = { [weak self] flags in self?.shortcut(nil, flags) ?? false }
        tap.onPointer = { [weak self] in self?.invalidate() }
        tap.onFailure = { [weak self] status in
            self?.stoppedForFailure = true; self?.invalidate(); self?.onStatus?(status)
        }
        sources.onChange = { [weak self] in
            guard let self else { return }
            generation &+= 1
            if active == nil && sources.currentID != undoRecord?.targetSource { undoRecord = nil }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    func apply() {
        guard !stoppedForFailure else { return }
        waitingForAccess = false
        tap.configure([store.profile.undo, store.profile.protect])
        sources.configure(store.profile)
        invalidate()
        let excluded = Set(store.profile.excludedApps), enabled = store.profile.enabled
        typing.releaseAccessibility { !enabled || excluded.contains($0) }
        guard store.profile.enabled else { tap.stop(); onStatus?("Приостановлено"); return }
        guard AXIsProcessTrusted() else {
            waitingForAccess = true; tap.stop(); onStatus?("Нужен «Универсальный доступ»"); return
        }
        guard tap.start() else { onStatus?("macOS не разрешила обработку клавиатуры. Проверьте доступ."); return }
        InputDiagnostics.record("tap started map=\(sources.map != nil)")
        onStatus?(sources.map == nil ? "Добавьте русскую и английскую раскладки в macOS" : "Работает локально")
    }

    func stop() { tap.stop(); typing.releaseAccessibility { _ in true }; store.flush() }
    func retry() { stoppedForFailure = false; sources.reload(); spell.retry(); apply() }
    func becameActive() { if waitingForAccess { apply() } }
    @objc private func appChanged() {
        if waitingForAccess { apply(); return }
        // The caret in the new app may be inside existing text: corrected as usual, but not learned from.
        invalidate(); tap.relocateWord(); preparePending = true
    }
    private func invalidate() { generation &+= 1; undoRecord = nil; typing.forget() }

    // Only where the user types, not in every app brought to the front.
    private func prepareFront() {
        preparePending = false
        guard store.profile.enabled, let app = text.inputOwner(), app.processIdentifier != getpid(),
              let id = app.bundleIdentifier, !store.profile.excludedApps.contains(id) else { return }
        typing.prepare(app)
    }

    func halt(_ status: String) {
        undoRecord = nil; typing.forget(); stoppedForFailure = true
        tap.stop(replay: false)
        onStatus?(status)
    }

    private func key(_ code: UInt16, _ flags: Modifiers, _ repeated: Bool, _ typed: Typed?) -> Bool {
        generation &+= 1
        if preparePending { prepareFront() }
        if !repeated && shortcut(code, flags) { return true }
        if !flags.intersection([.command, .control, .option]).isEmpty ||
            [UInt16(48), 51, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(code) {
            undoRecord = nil
            return false
        }
        guard !repeated, [UInt16(49), 36, 76].contains(code), active == nil, !spell.busy else { return false }
        InputDiagnostics.record("boundary generation=\(generation)")
        let revision = generation
        // One event-triggered handoff lets the recipient insert the boundary. Never an idle timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { [weak self] in
            guard let self else { return }
            guard generation == revision, active == nil, store.profile.enabled else {
                InputDiagnostics.record("boundary became stale"); return
            }
            switch text.capture(boundary: true, exclusions: store.profile.excludedApps) {
            case .field(let snapshot) where text.mayBeRecased(snapshot):
                // Cocoa text views capitalize a sentence's first word on its space, asynchronously: let that land
                // first, then correct the recased word, instead of racing it inside the transaction.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    guard let self else { return }
                    guard generation == revision, active == nil else {
                        stale += 1; InputDiagnostics.record("boundary became stale after recase wait"); return
                    }
                    guard case .field(let settled) = text.capture(boundary: true, exclusions: store.profile.excludedApps) else {
                        InputDiagnostics.record("capture lost after recase wait"); return
                    }
                    correctField(settled, revision: revision)
                }
            case .field(let snapshot): correctField(snapshot, revision: revision)
            case .blocked(let reason): InputDiagnostics.record("capture blocked reason=\(reason)")
            case .unreadable(let reason):
                InputDiagnostics.record("capture unreadable reason=\(reason)")
                if let typed { correctTyped(typed, revision: revision) } else { InputDiagnostics.record("keys no typed word") }
            }
        }
        return false
    }

    private func correctField(_ snapshot: TextSnapshot, revision: UInt64) {
        InputDiagnostics.record("captured word length=\(snapshot.word.range.length) caret=\(snapshot.selection.location)")
        _ = spell.analyze(snapshot.word.word, map: sources.map, protected: store.immune,
                          spelling: store.profile.spelling) { [weak self] correction, available in
            guard let self else { return }
            InputDiagnostics.record("analyzed available=\(available) correction=\(correction != nil) stale=\(generation != revision)")
            guard available else { onStatus?("Словари недоступны"); return }
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
                corrections += 1
                undoRecord = UndoRecord(snapshot: current, replacement: replacement,
                                        previousSource: previous, targetSource: target)
                typing.forget()
                onStatus?(correction.kind == .layout ? "Исправлена раскладка" : "Исправлена опечатка")
            }
        }
    }

    private func shortcut(_ code: UInt16?, _ flags: Modifiers) -> Bool {
        guard store.profile.enabled, active == nil else { return false }
        let undo = store.profile.undo, protectBinding = store.profile.protect
        if undo.keyCode == code && undo.modifiers == flags { return undoLast() }
        guard protectBinding.keyCode == code && protectBinding.modifiers == flags else { return false }
        guard store.profile.protectedWords.count < 10_000 else { onStatus?("Словарь заполнен"); return false }
        switch text.capture(boundary: false, exclusions: store.profile.excludedApps) {
        case .field(let snapshot):
            if let record = undoRecord, CFEqual(record.snapshot.element, snapshot.element),
               snapshot.word.range.location == record.snapshot.word.range.location,
               snapshot.word.word == record.replacement {
                return undoLast { [weak self] in self?.protect(record.snapshot.word.word) }
            }
            // The boundary capture may have fallen back to keys in a readable app: undo that word, not the replacement.
            if undoRecord == nil && typing.canUndo { return undoTypedLater(then: true) }
            protect(snapshot.word.word)
            return true
        case .blocked: return false
        case .unreadable:
            if typing.canUndo { return undoTypedLater(then: true) }
            guard let typed = tap.typedWord().map(Retype.init(typed:)), Words.language(of: typed.word) != nil,
                  let pid = text.inputOwner()?.processIdentifier,
                  text.keystrokeRefusal(expecting: nil, pid: pid) == nil else { return false }
            protect(typed.word)
            return true
        }
    }

    func protect(_ word: String) {
        store.update { profile in
            let key = Words.normalized(word)
            if !profile.protectedWords.contains(key) { profile.protectedWords.append(key); profile.protectedWords.sort() }
        }
        onStatus?("Слово защищено от исправлений")
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
            onStatus?("Исходное слово и раскладка восстановлены")
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
            case .restored: onStatus?("Исправление пропущено, исходный ввод сохранен")
            case .uncertain:
                halt("Исход исправления не подтвержден. Обработка остановлена, отложенный ввод отменен.")
            }
            completion(outcome == .confirmed)
        })
        tap.beginGate(abort: transaction.expire, cancel: transaction.cancel)
        transaction.start()
    }
}
