import XCTest
@testable import KeytideCore

final class ShortcutTests: XCTestCase {
    func testValidationAcceptsSupportedConfigurableBindings() {
        XCTAssertTrue(Shortcut(keyCode: nil, modifiers: .option).valid)
        XCTAssertTrue(Shortcut(keyCode: nil, modifiers: .control).valid)
        XCTAssertTrue(Shortcut(keyCode: 12, modifiers: [.command, .shift], keyLabel: "Q").valid)
        XCTAssertTrue(Shortcut(keyCode: 12, modifiers: .option, keyLabel: "Q").valid)
    }

    func testValidationRejectsUnsafeOrOutOfRangeBindings() {
        XCTAssertFalse(Shortcut(keyCode: nil, modifiers: []).valid)
        XCTAssertFalse(Shortcut(keyCode: nil, modifiers: [.option, .shift]).valid)
        XCTAssertFalse(Shortcut(keyCode: 12, modifiers: .shift, keyLabel: "Q").valid)
        XCTAssertFalse(Shortcut(keyCode: 128, modifiers: .control, keyLabel: "D").valid)
        XCTAssertFalse(Shortcut(keyCode: 2, modifiers: Modifiers(rawValue: 16), keyLabel: "D").valid)
        XCTAssertFalse(Shortcut(keyCode: 2, modifiers: .control, keyLabel: String(repeating: "D", count: 17)).valid)
    }

    func testOverlapRequiresExactNormalizedBinding() {
        XCTAssertTrue(Shortcut.protect.overlaps(Shortcut(keyCode: 2, modifiers: .control, keyLabel: "d")))
        XCTAssertFalse(Shortcut.protect.overlaps(Shortcut(keyCode: 2, modifiers: [.control, .shift], keyLabel: "D")))
        XCTAssertFalse(Shortcut.protect.overlaps(Shortcut(keyCode: 3, modifiers: .control, keyLabel: "D")))
    }

    func testModifierTapFiresForConfiguredSolitaryModifier() {
        var tap = ModifierTap()

        XCTAssertNil(tap.changed(.control, previous: []))
        XCTAssertEqual(tap.changed([], previous: .control), .control)
    }

    func testModifierTapDoesNotFireOptionAfterAKeyChord() {
        var tap = ModifierTap()

        XCTAssertNil(tap.changed(.option, previous: []))
        tap.interrupt()
        XCTAssertNil(tap.changed([], previous: .option))
    }

    func testModifierTapDisarmsWhenAnotherModifierJoins() {
        var tap = ModifierTap()

        XCTAssertNil(tap.changed(.option, previous: []))
        XCTAssertNil(tap.changed([.option, .shift], previous: .option))
        XCTAssertNil(tap.changed([], previous: [.option, .shift]))
    }
}
