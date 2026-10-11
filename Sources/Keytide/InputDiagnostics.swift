import Foundation
import OSLog

enum InputDiagnostics {
    private static let enabled = UserDefaults.standard.bool(forKey: "DebugInput")
    private static let logger = Logger(subsystem: "dev.firexrwt.keytide", category: "input")

    // Opt-in developer diagnostics contain stages and AX metadata, never entered text.
    static func record(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let value = message()
        logger.notice("\(value, privacy: .public)")
    }
}
