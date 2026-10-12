import XCTest
@testable import KeytideCore

final class DiagnosticLogTests: XCTestCase {
    func testAppsBecomeNumbersStableWithinARun() {
        let log = DiagnosticLog(capacity: 10)
        let first = log.app("com.example.Messenger"), second = log.app("com.example.Browser")
        XCTAssertEqual(first, "app1")
        XCTAssertEqual(second, "app2")
        XCTAssertEqual(log.app("com.example.Messenger"), "app1", "the same app keeps its number")
        log.clear()
        XCTAssertEqual(log.app("com.example.Browser"), "app1", "numbers do not survive a clear")
    }

    func testLinesAreNumberedNotTimedAndBounded() {
        let log = DiagnosticLog(capacity: 3)
        for stage in ["boundary", "capture", "analyzed", "posted"] { log.record(stage) }
        XCTAssertEqual(log.lines, ["#2 capture", "#3 analyzed", "#4 posted"])
        for line in log.lines { XCTAssertNil(line.range(of: "[0-9]{2}:[0-9]{2}", options: .regularExpression), line) }
    }

    func testOneLineOfBoundedLengthPerRecord() {
        let log = DiagnosticLog(capacity: 5)
        log.record("first\nsecond\r" + String(repeating: "x", count: 500))
        XCTAssertEqual(log.lines.count, 1)
        XCTAssertFalse(log.lines[0].contains("\n") || log.lines[0].contains("\r"))
        XCTAssertLessThanOrEqual(log.lines[0].count, DiagnosticLog.lineLimit)
    }
}
