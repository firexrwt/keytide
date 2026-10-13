import AppKit
import ApplicationServices
import KeytideCore

// Lifecycle, key routing and shortcuts. The two correction paths live in Coordinator+Field.swift (readable fields of
// whitelisted apps) and Coordinator+Typing.swift (everywhere else).
final class Coordinator {
    let store: ProfileStore
    let sources = InputSources()
    let spell = SpellService()
    let tap = EventTap()
    let text = FocusedText()
    var onStatus: ((String) -> Void)?
    // The system's list of layouts changed while running: Settings shows the new list.
    var onLayouts: (() -> Void)?
    // Internal, not private: the correction paths live in the extensions.
    var corrections = 0
    var undos = 0
    var stale = 0
    var generation: UInt64 = 0
    var active: UUID?
    var undoRecord: UndoRecord?
    // `UndoWindow.clock` of the last posted correction, on either path: each one replaces the previous undo state.
    var correctedAt = -TimeInterval.infinity
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
        sources.onListChange = { [weak self] in
            guard let self else { return }
            sources.reload(); apply(); onLayouts?()
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
        guard store.profile.enabled else { tap.stop(); onStatus?(tr("status.paused")); return }
        guard AXIsProcessTrusted() else {
            waitingForAccess = true; tap.stop(); onStatus?(tr("status.needsAccess")); return
        }
        guard tap.start() else { onStatus?(tr("status.tapRefused")); return }
        InputDiagnostics.record("tap started map=\(sources.map != nil)")
        onStatus?(sources.map == nil ? tr("status.addLayouts") : tr("status.running"))
    }

    // Correcting right now: false while paused, halted, without access or without both layouts.
    var working: Bool { tap.isRunning && sources.map != nil }

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
        switch KeyRole.of(code, flags: flags, repeated: repeated) {
        case .edit: undoRecord = nil; return false
        case .typing: return false
        case .boundary: break
        }
        guard active == nil, !spell.busy else { return false }
        // No counter: differences between boundaries would show how many keys were typed, also in excluded apps.
        InputDiagnostics.record("boundary")
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

    private func shortcut(_ code: UInt16?, _ flags: Modifiers) -> Bool {
        guard store.profile.enabled, active == nil else { return false }
        let undo = store.profile.undo, protectBinding = store.profile.protect
        if undo.keyCode == code && undo.modifiers == flags { return undoAllowed() && undoLast() }
        guard protectBinding.keyCode == code && protectBinding.modifiers == flags else { return false }
        guard store.profile.protectedWords.count < 10_000 else { onStatus?(tr("status.dictionaryFull")); return false }
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
        onStatus?(tr("status.protected"))
    }

    // The undo shortcut, unlike the deliberate Control+D, can be hit by accident: it acts only within `UndoWindow`
    // of the last correction, and not after a scroll since then (a scroll voided the undo when it went through the
    // tap). One lookup per press, nothing per scroll.
    private func undoAllowed() -> Bool {
        let now = UndoWindow.clock
        return UndoWindow.isOpen(since: correctedAt, now: now) &&
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel) > now - correctedAt
    }
}
