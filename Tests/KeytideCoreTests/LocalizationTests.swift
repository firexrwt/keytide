import XCTest

// The interface lives in Resources/<lang>.lproj/Localizable.strings. These checks read the sources, so a missing
// translation or a hard-coded Russian string fails the release CI instead of reaching users.
final class LocalizationTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func strings(_ language: String) throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(object as? [String: String], "\(language) strings")
    }

    private func sources(_ folder: String) throws -> [(name: String, text: String)] {
        let directory = root.appendingPathComponent(folder)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }
            .map { ($0, try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)) }
    }

    // Every % sequence in a value: tr() passes strings only, so anything but %@ / %n$@ would crash or misprint.
    private func placeholders(_ value: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:[0-9]+\\$)?[^%\\s]{0,3}")
        return pattern.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .map { (value as NSString).substring(with: $0.range) }.sorted()
    }

    func testBothLanguagesMatchKeyForKey() throws {
        let english = try strings("en"), russian = try strings("ru")
        XCTAssertEqual(Set(english.keys), Set(russian.keys))
        let allowed = try NSRegularExpression(pattern: "^%(?:[0-9]+\\$)?@")
        for (key, value) in english {
            let other = russian[key] ?? ""
            XCTAssertFalse(value.isEmpty || other.isEmpty, key)
            let found = placeholders(value)
            XCTAssertEqual(found, placeholders(other), "placeholders of \(key)")
            for placeholder in found {
                XCTAssertNotNil(allowed.firstMatch(in: placeholder, range: NSRange(placeholder.startIndex..., in: placeholder)),
                                "only %@ placeholders: \(key) has \(placeholder)")
                if found.count > 1 { XCTAssertTrue(placeholder.contains("$"), "numbered placeholders in \(key)") }
            }
            for text in [value, other] {
                XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "ASCII hyphen only: \(key)")
            }
        }
    }

    func testEveryKeyTheCodeUsesExistsAndNoneIsUnused() throws {
        let english = try strings("en")
        let call = try NSRegularExpression(pattern: "(?:\\btr|NSLocalizedString)\\(\\s*\"([a-zA-Z0-9._-]+)\"")
        var used = Set<String>()
        for (_, text) in try sources("Sources/Keytide") + sources("Sources/KeytideCore") {
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert((text as NSString).substring(with: match.range(at: 1)))
            }
        }
        XCTAssertGreaterThan(used.count, 50, "the scan itself must find the calls")
        for key in used.sorted() { XCTAssertNotNil(english[key], "missing key \(key)") }
        for key in Set(english.keys).subtracting(used).sorted() { XCTFail("unused key \(key)") }
    }

    // The certificate pinned in the release workflow is the one the About tab recognizes as official.
    func testTheReleaseCertificateIsPinnedInOnePlaceOnly() throws {
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
        let installer = try String(contentsOf: root.appendingPathComponent("Sources/Keytide/UpdateInstaller.swift"),
                                   encoding: .utf8)
        let leaf = try NSRegularExpression(pattern: "leaf = H\"([0-9a-f]{40})\"")
        let match = try XCTUnwrap(leaf.firstMatch(in: workflow, range: NSRange(workflow.startIndex..., in: workflow)))
        let hash = (workflow as NSString).substring(with: match.range(at: 1))
        XCTAssertTrue(installer.contains("releaseLeaf = \"\(hash)\""), "UpdateInstaller.releaseLeaf must equal \(hash)")
    }

    func testNoRussianTextIsHardCodedInTheApp() throws {
        // SpellService checks the system dictionaries with two known words; those are data, not interface.
        let allowed: Set<String> = ["\"привет\"", "\"ывафывфывфы\""]
        let literal = try NSRegularExpression(pattern: "\"[^\"\\n]*[А-Яа-яЁё][^\"\\n]*\"")
        for (name, text) in try sources("Sources/Keytide") {
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let string = String(line)
                for match in literal.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
                    let found = (string as NSString).substring(with: match.range)
                    XCTAssertTrue(allowed.contains(found), "\(name): \(found)")
                }
            }
        }
    }
}
