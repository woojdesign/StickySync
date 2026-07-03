// RemindNLParserTests.swift
//
// 0.12.2: pins the NL parser with deterministic `now`. Covers the
// custom rules ("in 30 min", "tomorrow morning", "next monday
// evening") + the NSDataDetector fall-through + future-only clamp.

import XCTest
@testable import StickySync

final class RemindNLParserTests: XCTestCase {

    private var cal: Calendar!

    override func setUp() {
        super.setUp()
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int,
                      _ h: Int = 12, _ min: Int = 0) -> Date {
        DateComponents(calendar: cal, timeZone: cal.timeZone,
                       year: y, month: m, day: d,
                       hour: h, minute: min).date!
    }

    // MARK: - Relative "in N unit"

    func testIn30Min() {
        let now = date(2026, 7, 3, 14, 30)
        let d = RemindNLParser.parse("in 30 minutes", now: now, calendar: cal)
        XCTAssertEqual(d, now.addingTimeInterval(30 * 60))
    }

    func testIn5Min_ShortForm() {
        let now = date(2026, 7, 3, 14, 30)
        let d = RemindNLParser.parse("in 5 min", now: now, calendar: cal)
        XCTAssertEqual(d, now.addingTimeInterval(5 * 60))
    }

    func testIn2Hours() {
        let now = date(2026, 7, 3, 14, 0)
        let d = RemindNLParser.parse("in 2 hours", now: now, calendar: cal)
        XCTAssertEqual(d, now.addingTimeInterval(2 * 3600))
    }

    func testIn1Hour_Singular() {
        let now = date(2026, 7, 3, 14, 0)
        XCTAssertEqual(RemindNLParser.parse("in 1 hour", now: now, calendar: cal),
                       now.addingTimeInterval(3600))
    }

    func testIn3Days() {
        let now = date(2026, 7, 3, 14, 0)
        XCTAssertEqual(RemindNLParser.parse("in 3 days", now: now, calendar: cal),
                       now.addingTimeInterval(3 * 86400))
    }

    // MARK: - Day-of-week + time-of-day

    func testTomorrowMorning() {
        let now = date(2026, 7, 3, 14, 0)
        let d = RemindNLParser.parse("tomorrow morning", now: now, calendar: cal)
        XCTAssertEqual(d, date(2026, 7, 4, 9, 0))
    }

    func testTomorrowEvening() {
        let now = date(2026, 7, 3, 14, 0)
        let d = RemindNLParser.parse("tomorrow evening", now: now, calendar: cal)
        XCTAssertEqual(d, date(2026, 7, 4, 19, 0))
    }

    func testTomorrow_NoTime_Defaults9am() {
        let now = date(2026, 7, 3, 14, 0)
        let d = RemindNLParser.parse("tomorrow", now: now, calendar: cal)
        XCTAssertEqual(d, date(2026, 7, 4, 9, 0))
    }

    func testTonight_Defaults9pm() {
        let now = date(2026, 7, 3, 14, 0)
        let d = RemindNLParser.parse("tonight", now: now, calendar: cal)
        XCTAssertEqual(d, date(2026, 7, 3, 21, 0))
    }

    func testNextMondayMorning_FromFriday() {
        let now = date(2026, 7, 3, 14, 0)  // Friday
        let d = RemindNLParser.parse("next monday morning", now: now, calendar: cal)
        XCTAssertEqual(d, date(2026, 7, 6, 9, 0))
    }

    /// "next monday" without leading "next" also works.
    func testMondayEvening_Implied() {
        let now = date(2026, 7, 3, 14, 0)
        let d = RemindNLParser.parse("monday evening", now: now, calendar: cal)
        XCTAssertEqual(d, date(2026, 7, 6, 19, 0))
    }

    /// "next monday" from a Monday = 7 days out (never today).
    func testNextMonday_FromMonday_Is7DaysAway() {
        let monday = date(2026, 7, 6, 14, 0)
        let d = RemindNLParser.parse("next monday", now: monday, calendar: cal)
        XCTAssertEqual(d, date(2026, 7, 13, 9, 0))
    }

    // MARK: - NSDataDetector fall-through

    /// "tomorrow at 9am" should resolve via NSDataDetector or the
    /// custom rules. Either way, next-day 9am.
    func testTomorrowAt9am_Resolves() {
        let now = date(2026, 7, 3, 14, 0)
        // We accept either path; just assert the result is close.
        let d = RemindNLParser.parse("tomorrow at 9am", now: now, calendar: cal)
        XCTAssertNotNil(d)
        // Expect within an hour of tomorrow 9am (NSDataDetector
        // may vary by locale).
        if let d = d {
            let expected = date(2026, 7, 4, 9, 0)
            XCTAssertLessThan(abs(d.timeIntervalSince(expected)), 3600)
        }
    }

    // MARK: - Fallback / negative

    func testGarbage_ReturnsNil() {
        let now = date(2026, 7, 3, 14, 0)
        XCTAssertNil(RemindNLParser.parse("adsfadsfadsf", now: now, calendar: cal))
    }

    func testEmpty_ReturnsNil() {
        let now = date(2026, 7, 3, 14, 0)
        XCTAssertNil(RemindNLParser.parse("", now: now, calendar: cal))
        XCTAssertNil(RemindNLParser.parse("   ", now: now, calendar: cal))
    }
}
