import Foundation
import OSLog
import KeytideCore

// Opt-in diagnostics: what Keytide decided, never what was typed, which app it was or when (see DiagnosticLog).
// The trail lives in memory for Save Report; debug-level log entries are not stored by macOS. The switch turns
// itself off after 30 minutes; the DebugInput default turns it on at launch for development.
// PrivacyTests lists every value allowed inside a record() or note() string.
enum InputDiagnostics {
    static let window: TimeInterval = 1_800
    private static let logger = Logger(subsystem: "dev.firexrwt.keytide", category: "input")
    private static let trail = DiagnosticLog(capacity: 400)
    private static var expiry: DispatchWorkItem?
    // Main thread only (every record() caller and the About switch run there); note() may come from any thread
    // and touches only the locked trail.
    private(set) static var enabled = UserDefaults.standard.bool(forKey: "DebugInput")
    // Tells the About tab that the switch turned itself off.
    static var onChange: (() -> Void)?

    static func setEnabled(_ on: Bool) {
        enabled = on
        expiry?.cancel(); expiry = nil
        guard on else { return }
        let work = DispatchWorkItem { setEnabled(false); onChange?() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + window, execute: work)
    }

    static func record(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        keep(message())
    }

    // Rare events worth a line in every report (update failures), recorded even with diagnostics off.
    static func note(_ message: String) { keep(message) }

    // "app1", "app2": which app it was stays on this Mac.
    static func app(_ bundleID: String) -> String { trail.app(bundleID) }

    static var recent: [String] { trail.lines }

    private static func keep(_ value: String) {
        logger.debug("\(value, privacy: .public)")
        trail.record(value)
    }
}
