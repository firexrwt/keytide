import AppKit
import ServiceManagement
import KeytideCore

// Settings, General tab: access, launch at login, updates, corrections, layouts and shortcuts.
final class GeneralPane: NSObject {
    let view = Form.pane()
    private let store: ProfileStore
    private let engine: Coordinator
    private let updater: Updater
    // What Keytide is doing right now ("Working locally", "Layout corrected"), and results of this tab's actions.
    private let status = Form.status()
    private let login = NSButton(checkboxWithTitle: tr("settings.login"), target: nil, action: nil)
    private let updates = NSButton(checkboxWithTitle: tr("settings.autoUpdates"), target: nil, action: nil)
    private let spelling = NSButton(checkboxWithTitle: tr("settings.spelling"), target: nil, action: nil)
    private let learning = NSButton(checkboxWithTitle: tr("settings.learning"), target: nil, action: nil)
    private let clipboard = NSButton(checkboxWithTitle: tr("settings.clipboard"), target: nil, action: nil)
    private let undo = ShortcutRecorder(), protect = ShortcutRecorder()
    private let english = NSPopUpButton(), russian = NSPopUpButton()

    init(store: ProfileStore, engine: Coordinator, updater: Updater) {
        self.store = store; self.engine = engine; self.updater = updater
        super.init()
        for (control, action) in [(login, #selector(launchAtLogin)), (updates, #selector(automaticUpdates)),
                                  (spelling, #selector(options)), (learning, #selector(options)),
                                  (clipboard, #selector(options)),
                                  (english, #selector(sources)), (russian, #selector(sources))] as [(NSControl, Selector)] {
            control.target = self; control.action = action
        }
        undo.setAccessibilityLabel(tr("settings.undo.a11y"))
        protect.setAccessibilityLabel(tr("settings.protect.a11y"))
        Form.add(Form.label(tr("settings.header"), bold: true), status,
                 Form.row(Form.button(tr("settings.grantAccess"), self, #selector(permissions)),
                          Form.button(tr("settings.checkAccess"), self, #selector(retry))),
                 login, updates, spelling, learning, Form.label(tr("settings.learning.note")),
                 clipboard, Form.label(tr("settings.clipboard.note")),
                 Form.row(Form.label("EN"), english, Form.label("RU"), russian),
                 Form.label(tr("settings.hotkeys"), bold: true),
                 Form.row(Form.label(tr("settings.undo")), undo, Form.label(tr("settings.protectWord")), protect),
                 Form.label(tr("settings.hotkeys.note")), to: view)
        undo.onCapture = { [weak self] value in
            guard let self else { return false }
            guard !value.overlaps(store.profile.protect) else { show(tr("settings.shortcutTaken")); return false }
            store.update { $0.undo = value }; return true
        }
        protect.onCapture = { [weak self] value in
            guard let self else { return false }
            guard !value.overlaps(store.profile.undo) else { show(tr("settings.shortcutTaken")); return false }
            store.update { $0.protect = value }; return true
        }
    }

    func show(_ message: String) { status.stringValue = message }

    func refresh() {
        spelling.state = store.profile.spelling ? .on : .off
        learning.state = store.profile.learning ? .on : .off
        clipboard.state = store.profile.clipboard ? .on : .off
        updates.state = updater.automatic ? .on : .off
        undo.binding = store.profile.undo; protect.binding = store.profile.protect
        for (popup, language, selected) in [(english, Language.en, engine.sources.english?.id),
                                           (russian, Language.ru, engine.sources.russian?.id)] {
            popup.removeAllItems()
            for entry in engine.sources.entries where entry.language == language {
                popup.addItem(withTitle: entry.name); popup.lastItem?.representedObject = entry.id
                if entry.id == selected { popup.select(popup.lastItem) }
            }
            popup.isEnabled = popup.numberOfItems > 0
        }
        syncLogin()
    }

    @objc private func permissions() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func retry() { engine.retry() }
    // Machine-local state owned by macOS, not by the portable profile. Queried on refresh (only while Settings is
    // shown) and on toggle.
    @objc private func launchAtLogin() {
        let wanted = login.state == .on
        var failed = false
        do {
            if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { failed = true; show(tr("settings.login.error", error.localizedDescription)) }
        let status = SMAppService.mainApp.status
        if status == .requiresApproval {
            show(tr("settings.login.approve"))
            SMAppService.openSystemSettingsLoginItems()
        } else if !failed && wanted != (status == .enabled) {
            show(tr("settings.login.unchanged", String(status.rawValue)))
        }
        syncLogin()
    }
    private func syncLogin() { login.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    // Machine-local like the login item: not part of the portable profile.
    @objc private func automaticUpdates() { updater.setAutomatic(updates.state == .on) }
    @objc private func options() {
        store.update {
            $0.spelling = spelling.state == .on; $0.learning = learning.state == .on; $0.clipboard = clipboard.state == .on
        }
    }
    @objc private func sources() {
        store.update { $0.englishSource = english.selectedItem?.representedObject as? String
                       $0.russianSource = russian.selectedItem?.representedObject as? String }
    }
}
