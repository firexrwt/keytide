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

    // Scrolling is not tapped: Option + scroll must not read as a lone Option (the undo).
    func testModifierTapDisarmsWhenTheUserScrolledWhileHoldingIt() {
        var tap = ModifierTap()
        XCTAssertNil(tap.changed(.option, previous: [], now: 10))
        XCTAssertNil(tap.changed([], previous: .option, now: 10.3) { 10.1 })

        XCTAssertNil(tap.changed(.option, previous: [], now: 20))
        XCTAssertEqual(tap.changed([], previous: .option, now: 20.2) { 19.5 }, .option, "a scroll before the press")
    }

    func testTheUndoWindowClosesAfterTenSeconds() {
        XCTAssertTrue(UndoWindow.isOpen(since: 100, now: 100))
        XCTAssertTrue(UndoWindow.isOpen(since: 100, now: 110))
        XCTAssertFalse(UndoWindow.isOpen(since: 100, now: 110.01))
        XCTAssertFalse(UndoWindow.isOpen(since: 100, now: 99), "a clock that went back opens nothing")
    }

    func testKeyRoles() {
        XCTAssertEqual(KeyRole.of(49, flags: [], repeated: false), .boundary, "space")
        XCTAssertEqual(KeyRole.of(36, flags: [], repeated: false), .boundary, "Return")
        XCTAssertEqual(KeyRole.of(76, flags: [], repeated: false), .boundary, "keypad Enter")
        XCTAssertEqual(KeyRole.of(49, flags: .shift, repeated: false), .boundary, "Shift+space still ends a word")
        XCTAssertEqual(KeyRole.of(49, flags: [], repeated: true), .typing, "a held space corrects nothing")
        XCTAssertEqual(KeyRole.of(49, flags: .option, repeated: false), .edit, "Option+space is a chord")
        XCTAssertEqual(KeyRole.of(0, flags: .command, repeated: false), .edit, "Cmd+A")
        for code: UInt16 in [48, 51, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126] {
            XCTAssertEqual(KeyRole.of(code, flags: [], repeated: true), .edit, "key \(code) moves or edits")
        }
        XCTAssertEqual(KeyRole.of(5, flags: .shift, repeated: false), .typing, "Shift+G")
    }
}
