import AppKit
import Carbon
import ServiceManagement
import KeytideCore

// A plain-text report to attach to a bug: versions, settings, counts and this run's diagnostic stages. Never typed
// text: diagnostics log stages, lengths and app IDs only, and word lists are counted, not listed. English, so the
// issue tracker can read it whatever the interface language.
enum DiagnosticReport {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }
    static var system: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    static func text(store: ProfileStore, engine: Coordinator, updater: Updater) -> String {
        let profile = store.profile
        var lines = [
            "Keytide \(version)",
            "Signature: \(UpdateInstaller.signature.rawValue)",
            "macOS \(system), \(architecture), interface language \(L10n.language)",
            "Accessibility: \(AXIsProcessTrusted()), Secure Input now: \(IsSecureEventInputEnabled())",
            // The two layouts Keytide works with; others only counted (they say which languages a person types).
            "Layouts: EN \(engine.sources.english?.id ?? "-"), RU \(engine.sources.russian?.id ?? "-"), " +
                "\(engine.sources.entries.count) enabled in total",
            "Enabled: \(profile.enabled), typos: \(profile.spelling), learning: \(profile.learning), " +
                "automatic update check: \(updater.automatic), launch at login: \(SMAppService.mainApp.status == .enabled)",
            "Protected words: \(profile.protectedWords.count), learned: \(profile.learnedWords.count), " +
                "undo records: \(profile.rejectedWords.count)",
            "Excluded apps: \(profile.excludedApps.count)",
            "This run: corrections \(engine.corrections), undos \(engine.undos), skipped as stale \(engine.stale), " +
                "key events \(engine.tap.eventCount)",
            "Detailed diagnostics: \(InputDiagnostics.enabled ? "on" : "off (turn on in About, repeat the problem, save again)")",
            "GitHub issues are public: read this file before attaching it.",
            "",
            "Diagnostics of this run (numbered steps, apps as app1, app2; never text, app names or times):",
        ]
        // Kept in memory by InputDiagnostics; one line each, at most 300 characters.
        let recent = InputDiagnostics.recent.map { String($0.replacingOccurrences(of: "\n", with: " ").prefix(300)) }
        lines += recent.isEmpty ? ["(none)"] : recent
        return lines.joined(separator: "\n") + "\n"
    }

    // GitHub's issue form fills the fields whose ids match these query items.
    static var bugLink: URL? {
        var components = URLComponents(string: "https://github.com/firexrwt/keytide/issues/new")
        components?.queryItems = [URLQueryItem(name: "template", value: "bug_report.yml"),
                                  URLQueryItem(name: "version", value: version),
                                  URLQueryItem(name: "macos", value: "\(system), \(architecture)")]
        return components?.url
    }
}
