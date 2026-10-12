import Foundation
import OSLog

// Opt-in diagnostics: stages, lengths and app IDs, never entered text. They live in memory only (the last 400
// lines, for Save Report) and as debug-level log entries, which macOS keeps in memory and does not write to disk.
// The About switch lasts until Keytide quits; the DebugInput default turns it on at launch for development.
enum InputDiagnostics {
    private static let logger = Logger(subsystem: "dev.firexrwt.keytide", category: "input")
    private static let capacity = 400
    private static let lock = NSLock()
    private static var lines: [String] = []
    // Read and written on the main thread only (every record() caller and the About switch run there); note() may
    // come from any thread and touches only the locked lines.
    private(set) static var enabled = UserDefaults.standard.bool(forKey: "DebugInput")

    static func setEnabled(_ on: Bool) { enabled = on }

    static func record(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        keep(message())
    }

    // Rare events worth a line in every report (update failures), recorded even with diagnostics off.
    static func note(_ message: String) { keep(message) }

    static var recent: [String] { lock.lock(); defer { lock.unlock() }; return lines }

    private static func keep(_ value: String) {
        logger.debug("\(value, privacy: .public)")
        let stamp = Date().formatted(.iso8601.time(includingFractionalSeconds: true))
        lock.lock()
        if lines.count >= capacity { lines.removeFirst(lines.count - capacity + 1) }
        lines.append("\(stamp) \(value)")
        lock.unlock()
    }
}
