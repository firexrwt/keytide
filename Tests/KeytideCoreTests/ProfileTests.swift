import Foundation
import XCTest
@testable import KeytideCore

final class ProfileTests: XCTestCase {
    func testCompleteProfileRoundTripKeepsPortableSettingsAndBindings() throws {
        var profile = Profile()
        profile.enabled = false
        profile.spelling = false
        profile.learning = true
        profile.undo = Shortcut(keyCode: nil, modifiers: .control)
        profile.protect = Shortcut(keyCode: 12, modifiers: [.command, .shift], keyLabel: "Q")
        profile.protectedWords = ["hello", "привет"]
        profile.rejectedWords = ["world": 2]
        profile.excludedApps = ["com.example.Editor"]
        profile.englishSource = "com.apple.keylayout.US"
        profile.russianSource = "com.apple.keylayout.Russian"

        let decoded = try Profile.decode(JSONEncoder().encode(profile), complete: true)

        XCTAssertEqual(decoded.0, profile)
        XCTAssertTrue(decoded.1.isEmpty)
    }

    func testCompleteDecodeRejectsMinimalAndMisspelledSchemas() throws {
        let minimal = Data("{\"version\":1}".utf8)
        XCTAssertNoThrow(try Profile.decode(minimal))
        XCTAssertThrowsError(try Profile.decode(minimal, complete: true)) { error in
            XCTAssertEqual(error as? ProfileError, .unsupported)
        }

        let encoded = try JSONEncoder().encode(Profile())
        var misspelled = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        misspelled["spellling"] = misspelled.removeValue(forKey: "spelling")
        let misspelledData = try JSONSerialization.data(withJSONObject: misspelled)
        XCTAssertThrowsError(try Profile.decode(misspelledData, complete: true)) { error in
            XCTAssertEqual(error as? ProfileError, .unsupported)
        }
    }

    func testDecodeFallsBackPerInvalidFieldAndReportsWarnings() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "enabled": "yes",
            "spelling": 1,
            "learning": false,
            "undo": ["keyCode": 500, "modifiers": ["rawValue": 4], "keyLabel": "X"],
            "protectedWords": ["Good", "good", "two words", "123"],
            "rejectedWords": ["valid": 2, "zero": 0, "also": 3, "123": 1],
            "excludedApps": ["com.example.Editor", "bad app", "com.example.Editor"],
            "englishSource": "bad source!",
            "russianSource": "com.apple.keylayout.Russian"
        ])

        let (profile, warnings) = try Profile.decode(data)

        XCTAssertFalse(profile.enabled)
        XCTAssertTrue(profile.spelling)
        XCTAssertFalse(profile.learning)
        XCTAssertEqual(profile.undo, .undo)
        XCTAssertEqual(profile.protectedWords, ["good"])
        XCTAssertEqual(profile.rejectedWords, ["valid": 2])
        XCTAssertEqual(profile.excludedApps, ["com.example.Editor"])
        XCTAssertNil(profile.englishSource)
        XCTAssertEqual(profile.russianSource, "com.apple.keylayout.Russian")
        XCTAssertEqual(Set(warnings), [
            "enabled", "spelling", "undo", "protectedWords", "rejectedWords", "excludedApps", "englishSource"
        ])
    }

    func testPartialProfileMissingSafetyKeysPausesWhileFullProfileStaysEnabled() throws {
        let partial = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "enabled": true
        ])
        let partialProfile = try Profile.decode(partial).0
        XCTAssertFalse(partialProfile.enabled)

        let full = Profile()
        XCTAssertTrue(full.enabled)
        let fullProfile = try Profile.decode(JSONEncoder().encode(full)).0
        XCTAssertTrue(fullProfile.enabled)
    }

    func testDecodeRejectsBooleanOrUnsupportedVersion() throws {
        let booleanVersion = try JSONSerialization.data(withJSONObject: ["version": true])
        let futureVersion = try JSONSerialization.data(withJSONObject: ["version": 2])

        XCTAssertThrowsError(try Profile.decode(booleanVersion)) { error in
            XCTAssertEqual(error as? ProfileError, .unsupported)
        }
        XCTAssertThrowsError(try Profile.decode(futureVersion)) { error in
            XCTAssertEqual(error as? ProfileError, .unsupported)
        }
    }

    func testDecodeEnforcesByteLimitBeforeParsing() throws {
        let prefix = Data("{\"version\":1}".utf8)
        var exact = prefix
        exact.append(Data(repeating: 0x20, count: Profile.maximumBytes - prefix.count))
        XCTAssertNoThrow(try Profile.decode(exact))

        exact.append(0x20)
        XCTAssertThrowsError(try Profile.decode(exact)) { error in
            XCTAssertEqual(error as? ProfileError, .tooLarge)
        }
    }

    func testDecodeAcceptsProtectedWordCapAndRejectsOneAboveIt() throws {
        let atLimit = (0..<10_000).map(alphaWord)
        let acceptedData = try JSONSerialization.data(withJSONObject: ["version": 1, "protectedWords": atLimit])
        let accepted = try Profile.decode(acceptedData)
        XCTAssertEqual(accepted.0.protectedWords.count, 10_000)
        XCTAssertTrue(accepted.1.isEmpty)

        let aboveLimit = atLimit + [alphaWord(10_000)]
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "protectedWords": aboveLimit])

        let (profile, warnings) = try Profile.decode(data)

        XCTAssertTrue(profile.protectedWords.isEmpty)
        XCTAssertEqual(warnings, ["protectedWords"])
    }

    func testDecodeResetsOverlappingShortcuts() throws {
        var profile = Profile()
        profile.undo = .protect
        profile.protect = .protect

        let (decoded, warnings) = try Profile.decode(JSONEncoder().encode(profile))

        XCTAssertEqual(decoded.undo, .undo)
        XCTAssertEqual(decoded.protect, .protect)
        XCTAssertEqual(warnings, ["shortcuts"])
    }

    func testIdentifiersAreBoundedAndPortable() {
        XCTAssertTrue(Profile.validIdentifier("com.apple.keylayout.US-International_1"))
        XCTAssertFalse(Profile.validIdentifier(""))
        XCTAssertFalse(Profile.validIdentifier("contains space"))
        XCTAssertFalse(Profile.validIdentifier("contains/slash"))
        XCTAssertFalse(Profile.validIdentifier(String(repeating: "a", count: 257)))
    }

    func testLearningBecomesImmuneOnlyAfterTwoUndosWhenEnabled() {
        var profile = Profile()
        profile.recordUndo("Teh")
        XCTAssertTrue(profile.rejectedWords.isEmpty)

        profile.learning = true
        profile.recordUndo("Teh")
        XCTAssertFalse(profile.immuneWords.contains("teh"))
        profile.recordUndo("TEH")
        XCTAssertTrue(profile.immuneWords.contains("teh"))
        profile.recordUndo("teh")
        XCTAssertEqual(profile.rejectedWords["teh"], 2)
    }

    func testLearningIgnoresInvalidAndNewWordsAtCapacity() {
        var profile = Profile()
        profile.learning = true
        profile.recordUndo("two words")
        XCTAssertTrue(profile.rejectedWords.isEmpty)

        profile.rejectedWords = Dictionary(uniqueKeysWithValues: (0..<2_500).map { (alphaWord($0), 1) })
        profile.recordUndo("brandnew")
        XCTAssertNil(profile.rejectedWords["brandnew"])

        let existing = alphaWord(0)
        profile.recordUndo(existing.uppercased())
        XCTAssertEqual(profile.rejectedWords[existing], 2)
    }

    func testImmuneWordsNormalizesProtectedEntriesFromInMemoryEdits() {
        var profile = Profile()
        profile.protectedWords = ["MiXeD", "ПРИВЕТ"]

        XCTAssertTrue(profile.immuneWords.contains("mixed"))
        XCTAssertTrue(profile.immuneWords.contains("привет"))
    }

    func testLearnedWordsListsOnlyImmuneEntriesAndForgetRemovesThem() {
        var profile = Profile()
        profile.learning = true
        profile.rejectedWords = ["ghbdtn": 2, "rfr": 1, "lf": 2]
        XCTAssertEqual(profile.learnedWords, ["ghbdtn", "lf"])
        profile.forget("GHBDTN")
        XCTAssertEqual(profile.learnedWords, ["lf"])
        XCTAssertFalse(profile.immuneWords.contains("ghbdtn"))
        XCTAssertEqual(profile.rejectedWords["rfr"], 1)
    }

    func testDefaultExclusionsAreValidAndCoverEditors() {
        let apps = Profile().excludedApps
        XCTAssertTrue(apps.allSatisfy(Profile.validIdentifier))
        XCTAssertEqual(Set(apps).count, apps.count)
        XCTAssertTrue(["com.apple.Terminal", "com.apple.dt.Xcode", "dev.zed.Zed", "com.mitchellh.ghostty"].allSatisfy(apps.contains))
    }

    private func alphaWord(_ value: Int) -> String {
        var number = value
        var suffix = ""
        repeat {
            suffix.append(Character(UnicodeScalar(97 + number % 26)!))
            number /= 26
        } while number > 0
        return "word" + suffix
    }
}
