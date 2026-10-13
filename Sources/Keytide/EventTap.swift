import AppKit
import KeytideCore

// A word finished by a space, with the input serial at that space. `edited`: it started after a click, a caret key,
// a chord, an app switch or a Backspace past its start, so it may be the end of a longer word the key stream never
// saw. `field`: the word was read from this element; the burst is then refused unless that element confirms it.
struct Typed {
    let retype: Retype
    let serial: UInt64
    var edited = false
    var field: AXUIElement?
}

final class EventTap {
    static let marker = Int64.random(in: 1...Int64.max)
    var onKey: ((UInt16, Modifiers, Bool, Typed?) -> Bool)?
    var onModifier: ((Modifiers) -> Bool)?
    var onPointer: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private let lock = NSLock()
    private var bindings: [Shortcut] = []
    private var previous = Modifiers()
    private var tapState = ModifierTap()
    private var swallowed: Set<UInt16> = []
    private var held: [CGEvent]?
    private var timeout: DispatchWorkItem?
    private var abortGate: (() -> Void)?
    private var cancelGate: (() -> Void)?
    private var deadline = 0.0
    private var overflow = false
    private var gateSerial: UInt64 = 0
    private var word = TypedWord()
    private var inputSerial: UInt64 = 0
    private var events = 0
    // Written under the lock on the tap thread.
    var eventCount: Int { lock.lock(); defer { lock.unlock() }; return events }
    // Main thread, like start and stop.
    var isRunning: Bool { port != nil }

    func configure(_ bindings: [Shortcut]) {
        lock.lock(); self.bindings = bindings; lock.unlock()
    }

    var withinGate: Bool {
        hasTime(0)
    }

    func hasTime(_ seconds: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return held != nil && !overflow && ProcessInfo.processInfo.systemUptime + seconds < deadline
    }

    func serial() -> UInt64 { lock.lock(); defer { lock.unlock() }; return inputSerial }
    func typedWord() -> String? { lock.lock(); defer { lock.unlock() }; return word.current }
    // App switch or tap start: the caret may be anywhere, what is typed next is a new word marked as an edit.
    func relocateWord() { lock.lock(); word.relocate(); lock.unlock() }

    func start() -> Bool {
        guard port == nil else { return true }
        relocateWord()
        // No scrolling: a scroll changes no text, and every scroll event would pass through this tap (measured
        // 0.23 ms of CPU each). A lone modifier asks once, on release, whether a scroll happened while it was held.
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown,
                                  .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<EventTap>.fromOpaque(context).takeUnretainedValue()
                return owner.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port); self.port = nil; return false
        }
        self.source = source
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            let loop = CFRunLoopGetCurrent()
            lock.lock(); self.loop = loop; lock.unlock()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        thread.name = "Keytide input"; thread.qualityOfService = .userInteractive; thread.start()
        ready.wait()
        return true
    }

    func stop(replay: Bool = true) {
        finishGate(replay: replay)
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        lock.lock()
        let oldLoop = loop; loop = nil
        swallowed.removeAll(); tapState.interrupt(); previous = []; word.invalidate()
        lock.unlock()
        if let oldLoop { CFRunLoopStop(oldLoop) }
        source = nil; port = nil
    }

    // `since` refuses the gate when anything was pressed after that input; the check shares the event lock.
    @discardableResult func beginGate(abort: @escaping () -> Void, cancel: @escaping () -> Void,
                                      since input: UInt64? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // One holder at a time: a second one is refused, never stacked (the clipboard probe holds across main turns).
        guard held == nil else { return false }
        if let input, input != inputSerial { return false }
        held = []; abortGate = abort; cancelGate = cancel
        gateSerial &+= 1
        let serial = gateSerial
        deadline = ProcessInfo.processInfo.systemUptime + InputTransaction.admissionDuration; overflow = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            lock.lock(); let current = held != nil && gateSerial == serial; lock.unlock()
            if current {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    lock.lock(); let callback = gateSerial == serial && held != nil ? abortGate : nil; lock.unlock()
                    callback?()
                }
            }
        }
        timeout = work
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + InputTransaction.admissionDuration, execute: work)
        return true
    }

    @discardableResult func finishGate(replay: Bool = true) -> Bool {
        lock.lock()
        timeout?.cancel(); timeout = nil; abortGate = nil; cancelGate = nil
        let intact = held != nil && !overflow
        let queued = held ?? []; held = nil
        // Dropped input never reached the app, so a word built from it is wrong.
        if !(replay && intact) && !queued.isEmpty { word.invalidate() }
        lock.unlock()
        guard replay && intact else { return intact }
        for event in queued {
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cgSessionEventTap)
        }
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                lock.lock(); let callback = cancelGate; lock.unlock()
                callback?(); stop(replay: false)
                onFailure?(tr("status.tapStopped"))
            }
            return false
        }
        lock.lock(); events += 1; lock.unlock()
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            lock.lock(); let consumed = swallowed.remove(code) != nil; lock.unlock()
            if consumed { return true }
        }
        let flags = Self.modifiers(event.flags)
        lock.lock()
        if held != nil {
            // Held input is replayed in this order, so the word follows it now.
            _ = record(type, code, flags, event)
            let copy = event.copy()
            if held!.count >= 64 || copy == nil {
                if let copy { held!.append(copy) }
                let callback = cancelGate
                overflow = true; lock.unlock()
                // Terminal cancellation keeps the queue bounded, including the triggering event.
                DispatchQueue.main.sync { callback?() }
                return true
            }
            held!.append(copy!)
            lock.unlock()
            return true
        }
        lock.unlock()
        if type == .flagsChanged {
            let now = ProcessInfo.processInfo.systemUptime
            lock.lock()
            let released = tapState.changed(flags, previous: previous, now: now) {
                now - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel)
            }
            previous = flags
            lock.unlock()
            if let released { DispatchQueue.main.async { [weak self] in _ = self?.onModifier?(released) } }
            return false
        }
        lock.lock(); tapState.interrupt(); lock.unlock()
        if type == .keyUp {
            return false
        }
        if type == .keyDown {
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            lock.lock(); let wasConsumed = swallowed.contains(code); lock.unlock()
            if wasConsumed { return true }
            lock.lock()
            let chord = bindings.contains { $0.keyCode == code && $0.modifiers == flags }
            let typed = chord ? nil : record(type, code, flags, event)
            lock.unlock()
            if !chord {
                DispatchQueue.main.async { [weak self] in _ = self?.onKey?(code, flags, repeated, typed) }
                return false
            }
            let consumed = DispatchQueue.main.sync { onKey?(code, flags, repeated, nil) == true }
            lock.lock()
            if consumed { swallowed.insert(code) } else { _ = record(type, code, flags, event) }
            lock.unlock()
            return consumed
        }
        lock.lock(); _ = record(type, code, flags, event); lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onPointer?() }
        return false
    }

    // Caller holds lock. Mirrors what the focused app receives: every user key press or pointer event moves the serial.
    private func record(_ type: CGEventType, _ code: UInt16, _ flags: Modifiers, _ event: CGEvent) -> Typed? {
        switch type {
        case .keyDown:
            inputSerial &+= 1
            let serial = inputSerial
            guard let retype = word.key(code, flags, text: Self.text(event)) else {
                // A plain space after a word whose characters the keys could not show: only a readable field can
                // name it. An empty word (double space) needs no field read at all.
                guard code == 49, flags.intersection([.command, .control, .option]).isEmpty,
                      word.finishedUnknown else { return nil }
                return Typed(retype: Retype(run: ""), serial: serial, edited: true)
            }
            return Typed(retype: retype, serial: serial, edited: word.finishedAfterEdit)
        case .keyUp, .flagsChanged: return nil
        default:
            // A click may move the caret into existing text: refuse a pending correction, and what follows is an edit.
            inputSerial &+= 1; word.relocate(); return nil
        }
    }

    // Stack buffer: no heap work per key press. nil when the characters cannot be read in full.
    private static func text(_ event: CGEvent) -> String? {
        var units: (UniChar, UniChar, UniChar, UniChar) = (0, 0, 0, 0)
        var length = 0
        return withUnsafeMutableBytes(of: &units) { raw in
            let buffer = raw.bindMemory(to: UniChar.self)
            event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length,
                                           unicodeString: buffer.baseAddress)
            // A full buffer may be a truncated longer string: unknown, not a wrong character count.
            guard length >= 0, length < buffer.count else { return nil }
            return String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(length)), as: UTF16.self)
        }
    }

    static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var result = Modifiers()
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        return result
    }
}
