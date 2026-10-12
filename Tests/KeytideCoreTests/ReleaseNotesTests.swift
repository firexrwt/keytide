import XCTest
@testable import KeytideCore

final class ReleaseNotesTests: XCTestCase {
    // A release without notes would show nothing after the update: the gate runs in the release CI job.
    func testTheShippedVersionHasNotesInBothLanguages() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(Set(ReleaseNotes.languages(for: version)), ["en", "ru"], "notes for \(version)")
        let english = try XCTUnwrap(ReleaseNotes.lines(for: version, language: "en"))
        let russian = try XCTUnwrap(ReleaseNotes.lines(for: version, language: "ru"))
        XCTAssertEqual(english.count, russian.count, "the two languages say the same things")
        for line in english + russian {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), "ASCII hyphen only: \(line)")
        }
    }

    func testOtherLanguagesGetEnglishAndUnknownVersionsNothing() {
        XCTAssertEqual(ReleaseNotes.lines(for: "0.1.2", language: "de"), ReleaseNotes.lines(for: "0.1.2", language: "en"))
        XCTAssertNil(ReleaseNotes.lines(for: "0.0.0", language: "en"))
    }
}
