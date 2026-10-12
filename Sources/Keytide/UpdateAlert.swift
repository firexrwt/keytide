import AppKit
import KeytideCore

// The answer to a manual "Check for Updates" is always a window, so the result is never only a tooltip.
// Automatic checks never show one: they only add the menu item. One alert at a time: a second check or error
// while one is open is dropped (its result is in the status line).
enum UpdateAlert {
    private static var presenting = false

    static func current(_ current: Version, published: Version?) {
        let alert = NSAlert()
        alert.messageText = tr("update.current.title")
        alert.informativeText = tr("update.current.text", current.description, (published ?? current).description)
        alert.addButton(withTitle: tr("update.ok"))
        run(alert)
    }

    // The answer may arrive while the user types elsewhere: Return must not start an update, only a click does.
    static func available(_ release: ReleaseInfo, current: Version, install: () -> Void) {
        let alert = NSAlert()
        alert.messageText = tr("update.available.title", release.version.description)
        alert.informativeText = tr("update.available.text", current.description)
        alert.addButton(withTitle: tr("update.install")).keyEquivalent = ""
        alert.addButton(withTitle: tr("update.later")).keyEquivalent = "\u{1b}"
        if run(alert) == .alertFirstButtonReturn { install() }
    }

    static func manual(_ version: Version, page: URL, current: Version) {
        let alert = NSAlert()
        alert.messageText = tr("update.manual.title", version.description)
        alert.informativeText = tr("update.manual.text", current.description)
        alert.addButton(withTitle: tr("update.openRelease"))
        alert.addButton(withTitle: tr("update.later"))
        if run(alert) == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
    }

    static func failed(_ reason: String, title: String = tr("update.failed.title")) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        if reason != title { alert.informativeText = reason }
        alert.addButton(withTitle: tr("update.ok"))
        run(alert)
    }

    @discardableResult private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse? {
        guard !presenting else { return nil }
        presenting = true
        defer { presenting = false }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
