import AppKit
import KeytideCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ProfileStore()
    private lazy var engine = Coordinator(store: store)
    private var settings: SettingsWindow?
    private var item: NSStatusItem!
    private var status = "Запуск..."

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.image
        item.button?.setAccessibilityLabel("Keytide")
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        engine.onStatus = { [weak self] text in
            self?.status = text; self?.item.button?.toolTip = "Keytide: " + text; self?.settings?.show(text)
        }
        store.onChange = { [weak self] in self?.engine.apply(); self?.settings?.refresh() }
        store.onError = { [weak self] message in self?.status = message; self?.settings?.show(message) }
        engine.apply()
        if let warning = store.warning { status = warning }
        if !AXIsProcessTrusted() { openSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { engine.becameActive() }
    func applicationWillTerminate(_ notification: Notification) { engine.stop() }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let info = NSMenuItem(title: status, action: nil, keyEquivalent: ""); info.isEnabled = false; menu.addItem(info)
        menu.addItem(.separator())
        add(store.profile.enabled ? "Приостановить" : "Включить", #selector(pause), to: menu)
        add("Настройки...", #selector(openSettings), to: menu)
        add("Проверить доступ", #selector(retry), to: menu)
        menu.addItem(.separator())
        add("Выйти из Keytide", #selector(quit), to: menu)
    }
    @objc private func pause() { store.update { $0.enabled.toggle() } }
    @objc private func openSettings() {
        if settings == nil { settings = SettingsWindow(store: store, engine: engine) }
        settings?.show(status); settings?.open()
    }
    @objc private func retry() { engine.retry() }
    @objc private func quit() { NSApp.terminate(nil) }
    private func add(_ title: String, _ selector: Selector, to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
    }
}
