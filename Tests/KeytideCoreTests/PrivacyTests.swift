import XCTest

// Every value Keytide may put into a diagnostic line, with the reason it says nothing about the person. A new value
// inside InputDiagnostics.record( or .note( fails this test until it is reviewed and added here.
final class PrivacyTests: XCTestCase {
    private static let allowed: [String: String] = [
        "\\(available)": "dictionaries loaded: a flag",
        "\\(correction != nil)": "a flag",
        "\\(generation != revision)": "a flag",
        "\\(sources.map != nil)": "a flag",
        "\\(reason)": "callers pass string literals only",
        "\\(step)": "transaction step enum or a literal update step",
        "\\(result)": "transaction result enum",
        "\\(outcome)": "transaction outcome enum",
        "\\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))": "duration of one correction, not a time of day",
        "\\(revive && previous != nil)": "a flag",
        "\\(result.rawValue)": "an AX error code",
        "\\(error.rawValue)": "an AX error code",
        "\\(InputDiagnostics.app(id))": "app1, app2: a number, never the app's ID",
        "\\(app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier)": "a flag: panel or not",
        "\\(role)": "AXTextField or AXTextArea (checked before)",
        "\\(known ? subrole : \"other\")": "a known AX subrole constant or 'other'",
        "\\(name)": "an AX attribute name constant",
        "\\(loose)": "a flag",
        "\\(choice.label)": "typed, field, again, probe or skip: a fixed label",
        "\\(shown.label)": "same, whole, changed or pending: a fixed label, never the word",
        "\\(retype.deletions)": "how many characters a correction replaced: only for corrected words",
        "\\(code)": "HTTP status or 'offline'",
    ]

    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    func testDiagnosticLinesCarryOnlyReviewedValues() throws {
        let folder = root.appendingPathComponent("Sources/Keytide")
        var calls = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            for line in text.split(separator: "\n") {
                guard let start = line.range(of: "InputDiagnostics.record(") ?? line.range(of: "InputDiagnostics.note(") else {
                    continue
                }
                calls += 1
                var call = String(line[start.upperBound...])
                for value in Self.allowed.keys { call = call.replacingOccurrences(of: value, with: "") }
                XCTAssertFalse(call.contains("\\("), "\(name): unreviewed value in a diagnostic line: \(line)")
            }
        }
        XCTAssertGreaterThan(calls, 30, "the scan itself must find the diagnostic calls")
    }
}
