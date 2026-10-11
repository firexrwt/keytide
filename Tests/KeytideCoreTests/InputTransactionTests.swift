import XCTest
@testable import KeytideCore

final class InputTransactionTests: XCTestCase {
    private final class Fixture {
        var pending: [() -> Void] = []
        var visited: [InputTransaction.Step] = []
        var outcomes: [InputTransaction.Outcome] = []
        var posts = 0
        var check: (InputTransaction.Step) -> Bool = { _ in true }
        var waiting: (InputTransaction.Step) -> Bool = { _ in false }
        lazy var transaction = InputTransaction(perform: { [self] step in
            visited.append(step)
            if waiting(step) { return .waiting }
            return check(step) ? .ready : .rejected
        }, post: { [self] in posts += 1 }, later: { [self] in pending.append($0) },
           completion: { [self] in outcomes.append($0) })

        func next() {
            guard !pending.isEmpty else { XCTFail("Expected a scheduled editor verification"); return }
            pending.removeFirst()()
        }
        func drain() {
            for _ in 0..<100 {
                guard !pending.isEmpty else { return }
                next()
            }
            XCTFail("Transaction exceeded its finite verification budget")
        }
    }

    func testConfirmWaitsForInsertionAndFinalCaret() {
        let fixture = Fixture()
        fixture.transaction.start()
        XCTAssertEqual(fixture.posts, 0)
        fixture.next()
        XCTAssertEqual(fixture.posts, 1)
        XCTAssertTrue(fixture.outcomes.isEmpty)
        fixture.next()
        XCTAssertTrue(fixture.outcomes.isEmpty)
        fixture.next()
        XCTAssertEqual(fixture.outcomes, [.confirmed])
        XCTAssertEqual(fixture.visited, [.prepare, .selected, .inserted, .confirmed])
    }

    func testPrePostFailureWaitsForAsynchronousSelectionRestoration() {
        let fixture = Fixture()
        var caretRestored = false
        fixture.check = { step in
            switch step {
            case .selected: return false
            case .restore:
                fixture.pending.append { caretRestored = true }
                return true
            case .restored: return caretRestored
            default: return true
            }
        }
        fixture.transaction.start()
        fixture.next()
        XCTAssertTrue(fixture.outcomes.isEmpty, "An AX setter response must not be treated as its completed effect")
        XCTAssertFalse(caretRestored)
        fixture.drain()
        XCTAssertEqual(fixture.posts, 0)
        XCTAssertEqual(fixture.outcomes, [.restored])
    }

    func testTimeoutWhileSelectedRestoresOnceAndNeverPosts() {
        let fixture = Fixture()
        fixture.transaction.start()
        fixture.transaction.abort()
        fixture.transaction.abort()
        fixture.drain()
        XCTAssertEqual(fixture.posts, 0)
        XCTAssertEqual(fixture.visited, [.prepare, .restore, .restored])
        XCTAssertEqual(fixture.outcomes, [.restored])
    }

    func testPostedFailureCannotRestoreUnchangedOriginalText() {
        let fixture = Fixture()
        fixture.check = { $0 != .inserted }
        fixture.transaction.start()
        fixture.drain()
        XCTAssertEqual(fixture.posts, 1)
        XCTAssertFalse(fixture.visited.contains(.restore))
        XCTAssertEqual(fixture.outcomes, [.uncertain])
    }

    func testTapFailureWhileRecoveringCannotReportSavedInput() {
        let fixture = Fixture()
        fixture.check = { $0 != .selected }
        fixture.transaction.start()
        fixture.next()
        fixture.transaction.cancel()
        fixture.drain()
        XCTAssertEqual(fixture.outcomes, [.uncertain])
        XCTAssertFalse(fixture.visited.contains(.restored))
        XCTAssertEqual(fixture.posts, 0)
    }

    func testExpiredRecoveryIsTerminal() {
        let fixture = Fixture()
        fixture.transaction.start()
        fixture.transaction.abort()
        fixture.transaction.expire()
        fixture.drain()
        XCTAssertEqual(fixture.outcomes, [.uncertain])
        XCTAssertFalse(fixture.visited.contains(.restored))
        XCTAssertEqual(fixture.posts, 0)
    }

    func testTimeoutAfterPostDoesNotRunQueuedCaretMutation() {
        let fixture = Fixture()
        fixture.transaction.start()
        fixture.next()
        fixture.transaction.abort()
        fixture.drain()
        XCTAssertEqual(fixture.visited, [.prepare, .selected])
        XCTAssertEqual(fixture.posts, 1)
        XCTAssertEqual(fixture.outcomes, [.uncertain])
    }

    func testTimeoutDuringFinalReadbackFinishesOnce() {
        let fixture = Fixture()
        fixture.transaction.start()
        fixture.next()
        fixture.next()
        fixture.transaction.abort()
        fixture.drain()
        fixture.transaction.abort()
        XCTAssertEqual(fixture.outcomes, [.uncertain])
        XCTAssertFalse(fixture.visited.contains(.confirmed))
        XCTAssertFalse(fixture.visited.contains(.restore))
    }

    func testRestorationFailureDoesNotReplay() {
        for failingStep in [InputTransaction.Step.restore, .restored] {
            let fixture = Fixture()
            fixture.check = { $0 != .prepare && $0 != failingStep }
            fixture.transaction.start()
            fixture.drain()
            XCTAssertEqual(fixture.posts, 0)
            XCTAssertEqual(fixture.outcomes, [.uncertain])
        }
    }

    func testWrongFinalTextRemainsUncertain() {
        let fixture = Fixture()
        fixture.check = { $0 != .confirmed }
        fixture.transaction.start()
        fixture.drain()
        XCTAssertEqual(fixture.outcomes, [.uncertain])
        XCTAssertFalse(fixture.visited.contains(.restore))
    }

    func testPreparationFailureCannotReachPost() {
        let fixture = Fixture()
        fixture.check = { $0 != .prepare }
        fixture.transaction.start()
        fixture.drain()
        fixture.transaction.start()
        XCTAssertEqual(fixture.posts, 0)
        XCTAssertEqual(fixture.visited, [.prepare, .restore, .restored])
        XCTAssertEqual(fixture.outcomes, [.restored])
    }

    func testDelayedInsertionIsVerifiedWithoutPostingAgain() {
        let fixture = Fixture()
        var insertionReads = 0
        fixture.waiting = { step in
            guard step == .inserted else { return false }
            insertionReads += 1
            return insertionReads < 4
        }
        fixture.transaction.start()
        fixture.next()
        for _ in 0..<3 {
            fixture.next()
            XCTAssertTrue(fixture.outcomes.isEmpty, "Known pending selection must not hard-stop before delivery")
            XCTAssertEqual(fixture.posts, 1, "Verification must never resend text")
        }
        fixture.drain()
        XCTAssertEqual(insertionReads, 4)
        XCTAssertEqual(fixture.outcomes, [.confirmed])
        XCTAssertFalse(fixture.visited.contains(.restore))
    }

    func testDelayedFinalCaretKeepsConfirmedWordAndPostsOnce() {
        let fixture = Fixture()
        var caretReads = 0
        fixture.waiting = { step in
            guard step == .confirmed else { return false }
            caretReads += 1
            return caretReads < 3
        }
        fixture.transaction.start()
        fixture.drain()
        XCTAssertEqual(fixture.posts, 1)
        XCTAssertEqual(caretReads, 3)
        XCTAssertEqual(fixture.outcomes, [.confirmed])
    }

    func testPendingInsertionHasFiniteReadBudget() {
        let fixture = Fixture()
        fixture.waiting = { $0 == .inserted }
        fixture.transaction.start()
        fixture.drain()
        XCTAssertEqual(fixture.posts, 1)
        XCTAssertEqual(fixture.visited.filter { $0 == .inserted }.count, InputTransaction.maximumChecks)
        XCTAssertEqual(fixture.outcomes, [.uncertain])
        XCTAssertFalse(fixture.visited.contains(.restore))
    }

    func testCancelPendingInsertionCannotPublishLateSuccess() {
        let fixture = Fixture()
        fixture.waiting = { $0 == .inserted }
        fixture.transaction.start()
        fixture.next()
        fixture.next()
        fixture.transaction.cancel()
        fixture.waiting = { _ in false }
        fixture.drain()
        XCTAssertEqual(fixture.posts, 1)
        XCTAssertEqual(fixture.outcomes, [.uncertain])
        XCTAssertFalse(fixture.visited.contains(.confirmed))
    }

    func testRepeatedTransactionsCanConfirmDelayedDelivery() {
        for _ in 0..<10 {
            let fixture = Fixture()
            var pending = true
            fixture.waiting = { step in
                guard step == .inserted else { return false }
                defer { pending = false }
                return pending
            }
            fixture.transaction.start()
            fixture.drain()
            XCTAssertEqual(fixture.posts, 1)
            XCTAssertEqual(fixture.outcomes, [.confirmed])
        }
    }
}
