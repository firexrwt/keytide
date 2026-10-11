import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import KeytideCore

final class SettingsWindow: NSObject {
    private let store: ProfileStore
    private let engine: Coordinator
    private let window: NSWindow
    private let status = NSTextField(wrappingLabelWithString: "")
    private let spelling = NSButton(checkboxWithTitle: "Исправлять очевидные опечатки", target: nil, action: nil)
    private let learning = NSButton(checkboxWithTitle: "Учиться на повторных отменах", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Запускать при входе в систему", target: nil, action: nil)
    private let updates = NSButton(checkboxWithTitle: "Проверять обновления автоматически (раз в сутки, GitHub)",
                                   target: nil, action: nil)
    private let updater: Updater
    private let undo = ShortcutRecorder(), protect = ShortcutRecorder()
    private let english = NSPopUpButton(), russian = NSPopUpButton()
    private let word = NSTextField(), apps = NSTextField()
    private let protectedList: WordTable
    private let learnedList: WordTable

    init(store: ProfileStore, engine: Coordinator, updater: Updater) {
        self.store = store; self.engine = engine; self.updater = updater
        protectedList = WordTable(label: "Защищенные слова", height: 100) { store.profile.protectedWords }
        learnedList = WordTable(label: "Выученные слова", height: 80) { store.profile.learnedWords }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 650),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        undo.setAccessibilityLabel("Сочетание для отмены исправления")
        protect.setAccessibilityLabel("Сочетание для защиты слова")
        window.title = "Keytide"
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        window.contentView = stack
        add(label("Раскладка под контролем", bold: true), to: stack)
        add(status, to: stack)
        add(row(button("Разрешить доступ", #selector(permissions)), button("Проверить доступ", #selector(retry))), to: stack)
        login.target = self; login.action = #selector(launchAtLogin)
        add(login, to: stack)
        updates.target = self; updates.action = #selector(automaticUpdates)
        add(updates, to: stack)
        spelling.target = self; spelling.action = #selector(options)
        learning.target = self; learning.action = #selector(options)
        add(spelling, to: stack)
        add(learning, to: stack)
        add(label("После двух отмен слово перестанет исправляться. История текста не хранится."), to: stack)
        english.target = self; english.action = #selector(sources)
        russian.target = self; russian.action = #selector(sources)
        add(row(label("EN"), english, label("RU"), russian), to: stack)
        add(label("Горячие клавиши", bold: true), to: stack)
        add(row(label("Отмена"), undo, label("Защитить слово"), protect), to: stack)
        add(label("Нажмите кнопку и введите сочетание. Одиночный модификатор тоже поддерживается.\nГлобальные сочетания могут перекрывать команды редактора."), to: stack)
        undo.onCapture = { [weak self] value in
            guard let self else { return false }
            guard !value.overlaps(self.store.profile.protect) else { self.show("Это сочетание уже занято."); return false }
            store.update { $0.undo = value }; return true
        }
        protect.onCapture = { [weak self] value in
            guard let self else { return false }
            guard !value.overlaps(self.store.profile.undo) else { self.show("Это сочетание уже занято."); return false }
            store.update { $0.protect = value }; return true
        }
        add(label("Защищенные слова", bold: true), to: stack)
        word.placeholderString = "Слово без пробелов"; word.setAccessibilityLabel("Слово для защиты")
        add(row(word, button("Добавить", #selector(addWord)), button("Удалить", #selector(removeWord))), to: stack)
        add(protectedList.scroll, to: stack)
        add(row(label("Выученные: не исправляются после двух отмен", bold: true),
                button("Забыть", #selector(forgetWord)), button("Забыть все", #selector(forgetAll))), to: stack)
        add(learnedList.scroll, to: stack)
        add(label("Исключения: bundle ID приложений через запятую", bold: true), to: stack)
        apps.setAccessibilityLabel("Исключенные приложения")
        add(row(apps, button("Сохранить", #selector(exclusions))), to: stack)
        add(row(button("Экспорт профиля", #selector(exportProfile)), button("Импорт профиля", #selector(importProfile))), to: stack)
        add(label("Профиль содержит словарь, настройки и данные обучения. Все хранится на этом Mac."), to: stack)
        refresh()
    }

    func show(_ message: String) { status.stringValue = message }
    func open() {
        refresh(); syncLogin()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func refresh() {
        spelling.state = store.profile.spelling ? .on : .off
        learning.state = store.profile.learning ? .on : .off
        updates.state = updater.automatic ? .on : .off
        undo.binding = store.profile.undo; protect.binding = store.profile.protect
        apps.stringValue = store.profile.excludedApps.joined(separator: ", ")
        for (popup, language, selected) in [(english, Language.en, engine.sources.english?.id),
                                           (russian, Language.ru, engine.sources.russian?.id)] {
            popup.removeAllItems()
            for entry in engine.sources.entries where entry.language == language {
                popup.addItem(withTitle: entry.name); popup.lastItem?.representedObject = entry.id
                if entry.id == selected { popup.select(popup.lastItem) }
            }
            popup.isEnabled = popup.numberOfItems > 0
        }
        protectedList.reload(); learnedList.reload()
    }

    @objc private func permissions() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func retry() { engine.retry() }
    // Machine-local state owned by macOS, not by the portable profile. Queried on open/toggle only.
    @objc private func launchAtLogin() {
        let wanted = login.state == .on
        var failed = false
        do {
            if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { failed = true; show("Автозапуск: " + error.localizedDescription) }
        let status = SMAppService.mainApp.status
        if status == .requiresApproval {
            show("Разрешите Keytide в «Объекты входа» Системных настроек.")
            SMAppService.openSystemSettingsLoginItems()
        } else if !failed && wanted != (status == .enabled) {
            show("Автозапуск не изменился, состояние macOS: \(status.rawValue)")
        }
        syncLogin()
    }
    private func syncLogin() { login.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    // Machine-local like the login item: not part of the portable profile.
    @objc private func automaticUpdates() { updater.setAutomatic(updates.state == .on) }
    @objc private func options() { store.update { $0.spelling = spelling.state == .on; $0.learning = learning.state == .on } }
    @objc private func sources() {
        store.update { $0.englishSource = english.selectedItem?.representedObject as? String
                       $0.russianSource = russian.selectedItem?.representedObject as? String }
    }
    @objc private func addWord() {
        let value = Words.normalized(word.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard Words.language(of: value) != nil, store.profile.protectedWords.count < 10_000 else { show("Введите одно слово до 64 символов."); return }
        store.update { if !$0.protectedWords.contains(value) { $0.protectedWords.append(value); $0.protectedWords.sort() } }
        word.stringValue = ""
    }
    @objc private func removeWord() {
        guard let value = protectedList.selected else { return }
        store.update { $0.protectedWords.removeAll { $0 == value } }
    }
    @objc private func forgetWord() {
        guard let value = learnedList.selected else { return }
        store.update { $0.forget(value) }
    }
    // Clears all learning data, including words undone once and not yet immune.
    @objc private func forgetAll() { store.update { $0.rejectedWords = [:] } }
    @objc private func exclusions() {
        let values = apps.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard values.count <= 200, values.allSatisfy(Profile.validIdentifier) else { show("Проверьте bundle ID приложений."); return }
        store.update { $0.excludedApps = Array(Set(values)).sorted() }
    }
    @objc private func exportProfile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Keytide-profile.json"
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            do {
                try SecureFile.write(store.encoded(), to: url)
                show("Профиль экспортирован.")
            }
            catch { show(error.localizedDescription) }
        }
    }
    @objc private func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            do { try store.importProfile(url); show("Профиль импортирован.") }
            catch { show(error.localizedDescription) }
        }
    }
    private func label(_ title: String, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: title)
        field.font = bold ? .systemFont(ofSize: 14, weight: .semibold) : .systemFont(ofSize: 12)
        field.textColor = bold ? .labelColor : .secondaryLabelColor
        return field
    }
    private func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
    private func row(_ views: NSView...) -> NSStackView { let row = NSStackView(views: views); row.spacing = 8; return row }
    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
    }
}
