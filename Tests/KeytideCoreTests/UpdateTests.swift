import XCTest
@testable import KeytideCore

final class UpdateTests: XCTestCase {
    private let current = Version("0.1.1")!

    private func release(tag: String = "v0.1.2", name: String = "Keytide-0.1.2.dmg", size: Any = 1_200_000,
                         url: String? = nil, page: String = "https://github.com/firexrwt/keytide/releases/tag/v0.1.2",
                         draft: Bool = false, prerelease: Bool = false, padding: Int = 0) -> Data {
        let link = url ?? "https://github.com/firexrwt/keytide/releases/download/\(tag)/\(name)"
        let object: [String: Any] = ["tag_name": tag, "draft": draft, "prerelease": prerelease, "html_url": page,
                                     "body": String(repeating: "x", count: padding),
                                     "assets": [["name": name, "size": size, "browser_download_url": link]]]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private let page = URL(string: "https://github.com/firexrwt/keytide/releases/tag/v0.1.2")!

    func testVersionParsingAndNumericOrder() {
        XCTAssertNotNil(Version("0.1.10"))
        XCTAssertTrue(Version("0.1.9")! < Version("0.1.10")!)
        XCTAssertTrue(Version("1.0.0")! > Version("0.99.99")!)
        XCTAssertEqual(Version("0.1.2"), Version("0.1.2"))
        for text in ["", "0.1", "0.1.2.3", "0..2", "0.1.x", "v0.1.2", "0.1.2 ", "0.1.９", "0.1.1234567", "-1.0.0"] {
            XCTAssertNil(Version(text), text)
        }
    }

    func testNewerReleaseIsAnUpdateWithALocallyBuiltPage() {
        guard case .update(let info) = ReleaseInfo.check(release(), current: current) else { return XCTFail() }
        XCTAssertEqual(info.version, Version("0.1.2"))
        XCTAssertEqual(info.dmg.absoluteString, "https://github.com/firexrwt/keytide/releases/download/v0.1.2/Keytide-0.1.2.dmg")
        XCTAssertEqual(info.page, page)
    }

    func testReleasePageNeverComesFromTheResponse() {
        let hostile = "https://github.com/firexrwt/keytide/releases/../../../attacker/fix/releases/tag/v0.1.2"
        guard case .update(let info) = ReleaseInfo.check(release(page: hostile), current: current) else { return XCTFail() }
        XCTAssertEqual(info.page, page)
    }

    func testSameOrOlderVersionIsCurrent() {
        XCTAssertEqual(ReleaseInfo.check(release(tag: "v0.1.1", name: "Keytide-0.1.1.dmg"), current: current), .current)
        XCTAssertEqual(ReleaseInfo.check(release(tag: "v0.1.0", name: "Keytide-0.1.0.dmg"), current: current), .current)
    }

    func testDraftsPrereleasesAndBadTagsAreIgnored() {
        XCTAssertEqual(ReleaseInfo.check(release(draft: true), current: current), .current)
        XCTAssertEqual(ReleaseInfo.check(release(prerelease: true), current: current), .current)
        XCTAssertEqual(ReleaseInfo.check(release(tag: "0.1.2"), current: current), .current)
        XCTAssertEqual(ReleaseInfo.check(release(tag: "v0.1.2-rc1"), current: current), .current)
    }

    // A newer version whose download cannot be trusted is announced for a manual look, never as "up to date".
    func testNewerVersionWithUnusableAssetNeedsManualInstall() {
        let manual = ReleaseCheck.manual(Version("0.1.2")!, page)
        XCTAssertEqual(ReleaseInfo.check(release(name: "Keytide-0.1.2.pkg"), current: current), manual)
        XCTAssertEqual(ReleaseInfo.check(release(url: "http://github.com/firexrwt/keytide/releases/download/v0.1.2/Keytide-0.1.2.dmg"), current: current), manual)
        XCTAssertEqual(ReleaseInfo.check(release(url: "https://github.com/someone/keytide/releases/download/v0.1.2/Keytide-0.1.2.dmg"), current: current), manual)
        XCTAssertEqual(ReleaseInfo.check(release(url: "https://github.com/firexrwt/keytide/releases/download/v0.1.1/Keytide-0.1.2.dmg"), current: current), manual)
        XCTAssertEqual(ReleaseInfo.check(release(url: "https://evil.example/Keytide-0.1.2.dmg"), current: current), manual)
        XCTAssertEqual(ReleaseInfo.check(release(size: 0), current: current), manual)
        XCTAssertEqual(ReleaseInfo.check(release(size: ReleaseInfo.maximumBytes + 1), current: current), manual)
        XCTAssertEqual(ReleaseInfo.check(release(size: "big"), current: current), manual)
    }

    func testJunkAndOversizedResponsesAreIgnored() {
        XCTAssertEqual(ReleaseInfo.check(Data("not json".utf8), current: current), .current)
        XCTAssertEqual(ReleaseInfo.check(Data("[1, 2]".utf8), current: current), .current)
        XCTAssertEqual(ReleaseInfo.check(Data("{}".utf8), current: current), .current)
        XCTAssertEqual(ReleaseInfo.check(release(padding: 1_100_000), current: current), .current)
    }
}
