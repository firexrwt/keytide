import AppKit
import KeytideCore

// The running version's notes in plain words: once, the first time Settings opens after an update, and from the
// menu at any time. Bundled with the app, no network.
enum WhatsNew {
    private static let seenKey = "WhatsNewSeen"
    private static var version: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }

    static var available: Bool { version.flatMap(ReleaseNotes.lines) != nil }

    // Not while Settings is open for the first-run Accessibility setup: that window has its own job.
    static func showOnce(attachedTo window: NSWindow) {
        guard AXIsProcessTrusted(), window.attachedSheet == nil, let version,
              UserDefaults.standard.string(forKey: seenKey) != version, let alert = alert(version) else { return }
        // Seen once the user closed it, not when it was merely queued.
        alert.beginSheetModal(for: window) { _ in UserDefaults.standard.set(version, forKey: seenKey) }
    }

    static func show() {
        guard let version, let alert = alert(version) else { return }
        UserDefaults.standard.set(version, forKey: seenKey)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func alert(_ version: String) -> NSAlert? {
        guard let lines = ReleaseNotes.lines(for: version) else { return nil }
        let alert = NSAlert()
        alert.messageText = "Что нового в Keytide \(version)"
        alert.informativeText = lines.map { "• " + $0 }.joined(separator: "\n\n")
        alert.addButton(withTitle: "Понятно")
        return alert
    }
}
