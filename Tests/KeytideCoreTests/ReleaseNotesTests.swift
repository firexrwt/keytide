import XCTest
@testable import KeytideCore

final class ReleaseNotesTests: XCTestCase {
    // A release without notes would show nothing after the update: the gate runs in the release CI job.
    func testTheShippedVersionHasNotes() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        let notes = try XCTUnwrap(ReleaseNotes.lines(for: version), "no release notes for \(version)")
        XCTAssertFalse(notes.isEmpty)
        for line in notes {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), "ASCII hyphen only: \(line)")
        }
    }

    func testUnknownVersionHasNoNotes() {
        XCTAssertNil(ReleaseNotes.lines(for: "0.0.0"))
    }
}
