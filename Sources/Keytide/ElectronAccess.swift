import AppKit
import ApplicationServices

// Electron builds its accessibility tree only for assistive tools, so its text fields do not answer until asked
// with AXManualAccessibility (documented by Electron for third-party tools). Keytide asks when such an app comes to
// the front or its field did not answer; a granted request is not repeated for 5 minutes, a failed one for 20 s.
// Measured on Claude desktop 2026-10-12: about +20 MB, no CPU change beyond noise. The tree also opens the app's
// content to every other accessibility client, so password managers never get it, and Keytide turns it off again
// (only where it was off before) when it quits, pauses or the app is excluded.
final class ElectronAccess {
    private static let attribute = "AXManualAccessibility" as CFString
    private static let renewal: TimeInterval = 300, backoff: TimeInterval = 20
    private static let never: Set<String> = ["com.bitwarden.desktop", "com.1password.1password",
                                             "com.1password.1password-launcher", "com.dashlane.dashlanephonefinal"]
    private struct Grant { let id: String; var at: TimeInterval; let wasOff: Bool }
    private var electron: [String: Bool] = [:]
    private var granted: [pid_t: Grant] = [:]
    private var failed: [pid_t: TimeInterval] = [:]

    // True when the attribute was set just now, so the tree is still being built. `revive`: a field did not answer
    // although the attribute was granted long ago; off and on again rebuilds a tree Chromium tore down in the
    // background (as FlicKey does; Chromium drops it after 5 minutes hidden).
    func request(for app: NSRunningApplication, revive: Bool) -> Bool {
        guard let id = app.bundleIdentifier, !Self.never.contains(id), isElectron(app, id) else { return false }
        let pid = app.processIdentifier, now = ProcessInfo.processInfo.systemUptime
        if let last = failed[pid], now - last < Self.backoff { return false }
        let previous = granted[pid]
        if let previous, now - previous.at < Self.renewal { return false }
        if granted.count >= 32 { granted = granted.filter { NSRunningApplication(processIdentifier: $0.key) != nil } }
        if failed.count >= 32 { failed.removeAll() }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.05)
        let wasOff = previous?.wasOff ?? !Self.isOn(element)
        if revive && previous != nil { _ = AXUIElementSetAttributeValue(element, Self.attribute, kCFBooleanFalse) }
        let result = AXUIElementSetAttributeValue(element, Self.attribute, kCFBooleanTrue)
        InputDiagnostics.record("electron accessibility requested revive=\(revive && previous != nil) result=\(result.rawValue)")
        if result == .success { granted[pid] = Grant(id: id, at: now, wasOff: wasOff); failed[pid] = nil } else { failed[pid] = now }
        return result == .success
    }

    // Turns the tree off again in apps where Keytide turned it on, for those whose bundle id matches.
    // Never while VoiceOver runs: the same switch would take the tree from its user.
    func release(where matches: (String) -> Bool) {
        for (pid, grant) in granted where matches(grant.id) {
            granted[pid] = nil
            guard grant.wasOff, !NSWorkspace.shared.isVoiceOverEnabled,
                  NSRunningApplication(processIdentifier: pid) != nil else { continue }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.05)
            let result = AXUIElementSetAttributeValue(element, Self.attribute, kCFBooleanFalse)
            InputDiagnostics.record("electron accessibility released result=\(result.rawValue)")
        }
    }

    private static func isOn(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return false }
        return (value as? Bool) == true || (value as? NSNumber)?.boolValue == true
    }

    private func isElectron(_ app: NSRunningApplication, _ id: String) -> Bool {
        if let known = electron[id] { return known }
        // Not cached while the bundle cannot be located: an updater may be replacing it.
        guard let bundle = app.bundleURL else { return false }
        let found = FileManager.default.fileExists(atPath:
            bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        if electron.count >= 64 { electron.removeAll() }
        electron[id] = found
        return found
    }
}
