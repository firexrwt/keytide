import AppKit
import KeytideCore

final class ShortcutRecorder: NSButton {
    var binding = Shortcut.undo { didSet { if monitor == nil { title = binding.label; setAccessibilityValue(title) } } }
    var onCapture: ((Shortcut) -> Bool)?
    private var monitor: Any?
    private var modifierTap = ModifierTap()
    private var previous = Modifiers()
    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self; action = #selector(record)
        title = binding.label
        setAccessibilityValue(title)
        setAccessibilityHelp("Нажмите и введите сочетание клавиш. Escape отменяет запись.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    @objc private func record() {
        stop()
        window?.makeFirstResponder(self)
        title = "Нажмите клавиши..."
        setAccessibilityValue(title)
        previous = []; modifierTap = ModifierTap()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let flags = Self.modifiers(event.modifierFlags)
            let candidate: Shortcut
            if event.type == .flagsChanged {
                let release = modifierTap.changed(flags, previous: previous)
                previous = flags
                guard let release else { return nil }
                candidate = Shortcut(keyCode: nil, modifiers: release)
            } else {
                modifierTap.interrupt()
                if event.keyCode == 53 { stop(); return nil }
                guard !event.isARepeat else { return nil }
                let names: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
                    117: "Del", 123: "←", 124: "→", 125: "↓", 126: "↑"]
                let label = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
                candidate = Shortcut(keyCode: event.keyCode, modifiers: flags, keyLabel: label)
            }
            if candidate.valid && onCapture?(candidate) == true { binding = candidate; stop() }
            else { NSSound.beep() }
            return nil
        }
    }

    override func resignFirstResponder() -> Bool { stop(); return true }
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; title = binding.label
        setAccessibilityValue(title)
    }
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Modifiers {
        var value = Modifiers()
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        return value
    }
}
