import XCTest
@testable import KeytideCore

final class ReleaseNotesTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func shippedVersion() throws -> String {
        let info = try XCTUnwrap(NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist")) as? [String: Any])
        return try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
    }

    // A release without notes would show nothing after the update: the gate runs in the release CI job.
    func testTheShippedVersionHasNotesInBothLanguages() throws {
        let version = try shippedVersion()
        XCTAssertEqual(Set(ReleaseNotes.languages(for: version)), ["en", "ru"], "notes for \(version)")
        let english = try XCTUnwrap(ReleaseNotes.lines(for: version, language: "en"))
        let russian = try XCTUnwrap(ReleaseNotes.lines(for: version, language: "ru"))
        XCTAssertEqual(english.count, russian.count, "the two languages say the same things")
        for line in english + russian {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), "ASCII hyphen only: \(line)")
        }
    }

    // The release CI drafts the GitHub release text from the "## <version> - " section, newest first.
    func testTheShippedVersionLeadsTheChangelog() throws {
        let version = try shippedVersion()
        let text = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "ASCII hyphen only")
        let lines = text.components(separatedBy: "\n")
        let head = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("## ") }, "no sections")
        XCTAssertNotNil(lines[head].range(of: "^## \(version) - \\d{4}-\\d{2}-\\d{2}$", options: .regularExpression),
                        "the first section must be \(version) with a date: \(lines[head])")
        let body = lines[(head + 1)...].prefix { !$0.hasPrefix("## ") }
        XCTAssertTrue(body.contains { $0.hasPrefix("- ") }, "the \(version) section lists no changes")
    }

    func testOtherLanguagesGetEnglishAndUnknownVersionsNothing() {
        XCTAssertEqual(ReleaseNotes.lines(for: "0.1.2", language: "de"), ReleaseNotes.lines(for: "0.1.2", language: "en"))
        XCTAssertNil(ReleaseNotes.lines(for: "0.0.0", language: "en"))
    }
}
