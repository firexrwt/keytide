import AppKit
import Carbon
import KeytideCore

// Reads the text left of the caret in a field that hides it from accessibility: selects it with Shift+Left, copies
// it, reads the clipboard and puts everything back (owner decision 2026-10-13; KeyRay does the same). The clipboard
// holds a marker and then the copied text for a few milliseconds; the user's own contents, every item and type, are
// restored at once. Keys the user presses meanwhile are held by the tap's gate and replayed after. The caller sends
// it only to a focus that shows an empty caret (`FocusedText.probeCaret`). Main thread only.
final class ClipboardProbe {
    // `refused`: no key was sent. `nothing`: keys were sent, no text came back (`timedOut`: the app copied nothing).
    enum Result { case refused, copied(String), nothing(timedOut: Bool) }

    private typealias Item = [(NSPasteboard.PasteboardType, Data)]
    // Hint for clipboard history apps (nspasteboard.org): our marker and the restore are not new user content.
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    // A password manager's copy: never touched. Putting it back would also defeat its clear-after timer, which checks
    // that the clipboard did not change.
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    // How long the copy may take (the first Cmd+C in a fresh document took over 120 ms), how long a copy that came too
    // late is watched for after the restore, and the field's moment to apply the collapsed selection.
    private static let wait: TimeInterval = 0.4, late: TimeInterval = 1.5, settle: TimeInterval = 0.04
    // A 1 ms poll gave no shorter window than 4 ms: the app's own copy takes most of it (pbwatch, 2026-10-13).
    private static let step = DispatchTimeInterval.milliseconds(4)
    // The snapshot is all or nothing and bounded: a clipboard that cannot be put back exactly is not touched.
    private static let maximumItems = 16, maximumBytes = 8 << 20

    private let tap: EventTap
    // The change count of a clipboard found not restorable: it is not read again until it changes.
    private var unrestorable: Int?
    init(tap: EventTap) { self.tap = tap }

    // `count`: characters to select, ending at the caret (the typed space included); `copyKey`: the key of Command+C in
    // the current layout; `stillThere`: the focus and caret are where the caller checked them, asked again once the
    // user's keys are held. `lost`: the user's held keys were dropped.
    func read(_ count: Int, copyKey: CGKeyCode, since serial: UInt64, stillThere: () -> Bool,
              completion: @escaping (_ result: Result, _ lost: Bool) -> Void) {
        let board = NSPasteboard.general
        func refuse(_ reason: String) { InputDiagnostics.record("clipboard refused reason=\(reason)"); completion(.refused, false) }
        guard (1...Words.maximumLength + 2).contains(count), !IsSecureEventInputEnabled() else { return refuse("input") }
        // Programmatic reads of the clipboard may be denied (an empty read would then wipe it on restore) or ask the
        // user in an alert in the middle of typing: only where access is silent.
        if #available(macOS 15.4, *), [.ask, .alwaysDeny].contains(board.accessBehavior) { return refuse("access") }
        let snapshotCount = board.changeCount
        guard snapshotCount != unrestorable else { return refuse("not restorable") }
        let items = board.pasteboardItems ?? []
        guard !items.contains(where: { $0.types.contains(Self.concealed) }) else { return refuse("concealed") }
        // Read before the gate opens: a slow clipboard owner never holds the user's keys.
        guard let saved = Self.snapshot(items) else { unrestorable = snapshotCount; return refuse("not restorable") }
        guard let source = CGEventSource(stateID: .privateState),
              tap.beginGate(abort: {}, cancel: {}, since: serial) else { return refuse("gate") }
        // The snapshot may have taken a while: the clipboard and the focus must still be the ones checked.
        guard board.changeCount == snapshotCount, stillThere() else {
            InputDiagnostics.record("clipboard refused reason=changed meanwhile")
            let intact = tap.finishGate()
            completion(.refused, !intact); return
        }
        let marker = "keytide-probe-" + UUID().uuidString
        board.prepareForNewContents(with: .currentHostOnly)
        board.setString(marker, forType: .string)
        board.setString("", forType: Self.transient)
        let before = board.changeCount
        func send(_ key: CGKeyCode, _ flags: CGEventFlags, down: Bool) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: EventTap.marker)
            event.post(tap: .cgSessionEventTap)
        }
        func post(_ key: CGKeyCode, _ flags: CGEventFlags) { send(key, flags, down: true); send(key, flags, down: false) }
        for _ in 0..<count { post(123, .maskShift) }
        // Command down, C, Command up: some apps look at the modifier keys, not only at the flags of C.
        send(55, .maskCommand, down: true); post(copyKey, .maskCommand); send(55, [], down: false)
        let started = ProcessInfo.processInfo.systemUptime
        // Not host-only: the copied word may already be offered to the user's other devices (Universal Clipboard),
        // and the restored contents must replace it there too. Returns the clipboard's change count after it.
        func restore() -> Int {
            func write() -> Bool {
                board.clearContents()
                return saved.isEmpty || board.writeObjects(saved.map { pairs in
                    let item = NSPasteboardItem()
                    for (type, data) in pairs { item.setData(data, forType: type) }
                    item.setData(Data(), forType: Self.transient)
                    return item
                })
            }
            if !write() && !write() { InputDiagnostics.record("clipboard restore failed") }
            return board.changeCount
        }
        // The copied word leaves the clipboard at once: a history app sees it only if it looks in these few
        // milliseconds. Right drops the selection at its right end, the caret where it was; the field gets a moment
        // to apply it before anything else is checked or typed (a Backspace must not meet the selection).
        // `restoring` false: a password manager copied during the probe, and its copy stays. The late-copy guard
        // watches from the typed space: any key held during the probe stops it, so a Command+C the user pressed
        // meanwhile (replayed after the gate) is never taken for the late copy.
        func finish(_ result: Result, restoring: Bool) {
            if restoring {
                let restored = restore()
                if case .copied = result {} else {
                    guardLateCopy(restored: restored, user: serial, restore: { _ = restore() })
                }
            }
            post(124, [])
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [self] in
                let intact = tap.finishGate()
                completion(result, !intact)
            }
        }
        // A clipboard the app cleared but has not written yet holds nothing to leak: wait for the text up to `wait`.
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now() + Self.step, repeating: Self.step, leeway: .nanoseconds(0))
        timer.setEventHandler {
            let types = board.changeCount != before ? board.types ?? [] : nil
            if let types, types.contains(Self.concealed) {
                timer.cancel(); finish(.nothing(timedOut: false), restoring: false)
            } else if let types, !types.isEmpty {
                // Something other than text (an image from a canvas) leaves at once too.
                timer.cancel()
                if let text = board.string(forType: .string), text != marker { finish(.copied(text), restoring: true) }
                else { finish(.nothing(timedOut: false), restoring: true) }
            } else if ProcessInfo.processInfo.systemUptime - started >= Self.wait {
                timer.cancel(); finish(.nothing(timedOut: true), restoring: true)
            }
        }
        timer.resume()
    }

    // Every item with every type read in full, or nil: data its owner does not provide, or over the bounds.
    private static func snapshot(_ items: [NSPasteboardItem]) -> [Item]? {
        guard items.count <= maximumItems else { return nil }
        var bytes = 0, saved: [Item] = []
        for item in items {
            var pairs: Item = []
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                bytes += data.count
                guard bytes <= maximumBytes else { return nil }
                pairs.append((type, data))
            }
            saved.append(pairs)
        }
        return saved
    }

    // A copy that did not come in time may still land after the restore and overwrite the user's clipboard. Until the
    // user presses a key or clicks (the only ways to copy something themselves), any change of the clipboard is that
    // late copy: put the user's contents back once more, unless it is a password manager's. Bounded, stops at the
    // first user input.
    private func guardLateCopy(restored: Int, user: UInt64, restore: @escaping () -> Void) {
        let board = NSPasteboard.general, started = ProcessInfo.processInfo.systemUptime
        func check() {
            guard tap.serial() == user, ProcessInfo.processInfo.systemUptime - started < Self.late else { return }
            guard board.changeCount == restored else {
                guard board.types?.contains(Self.concealed) != true else { return }
                restore(); InputDiagnostics.record("clipboard late copy put back"); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: check)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: check)
    }
}
