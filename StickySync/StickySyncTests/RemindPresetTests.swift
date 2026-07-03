// RemindPresetTests.swift
//
// 0.12.1: pins preset date computation with injected `now`. No
// wall-clock reads → tests are deterministic across midnight
// boundaries, DST, weekends, etc.

import XCTest
@testable import StickySync

final class RemindPresetTests: XCTestCase {

    private var cal: Calendar!

    override func setUp() {
        super.setUp()
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int,
                      _ h: Int = 12, _ min: Int = 0) -> Date {
        let comps = DateComponents(calendar: cal, timeZone: cal.timeZone,
                                    year: y, month: m, day: d,
                                    hour: h, minute: min)
        return comps.date!
    }

    // MARK: - In 30 minutes

    func testIn30Minutes_JustAdds30Minutes() {
        let now = date(2026, 7, 3, 14, 30)
        let fireAt = RemindPreset.in30Minutes.fireAt(now: now, calendar: cal)
        XCTAssertEqual(fireAt, date(2026, 7, 3, 15, 0))
    }

    // MARK: - Tomorrow 9am

    func testTomorrow9am_FromMidday() {
        let now = date(2026, 7, 3, 14, 30)
        let fireAt = RemindPreset.tomorrow9am.fireAt(now: now, calendar: cal)
        XCTAssertEqual(fireAt, date(2026, 7, 4, 9, 0))
    }

    func testTomorrow9am_FromLateNight_StillTomorrow() {
        let now = date(2026, 7, 3, 23, 59)
        let fireAt = RemindPreset.tomorrow9am.fireAt(now: now, calendar: cal)
        XCTAssertEqual(fireAt, date(2026, 7, 4, 9, 0))
    }

    func testTomorrow9am_FromEarlyMorning_StillTomorrow() {
        // Even at 5am, "tomorrow" means the NEXT calendar day, not
        // today. Matches how people talk.
        let now = date(2026, 7, 3, 5, 0)
        let fireAt = RemindPreset.tomorrow9am.fireAt(now: now, calendar: cal)
        XCTAssertEqual(fireAt, date(2026, 7, 4, 9, 0))
    }

    // MARK: - Next Monday 9am

    /// Friday July 3 2026 → next Monday is July 6.
    func testNextMonday_FromFriday() {
        let now = date(2026, 7, 3, 14, 0)  // Friday
        let fireAt = RemindPreset.nextMonday9am.fireAt(now: now, calendar: cal)
        XCTAssertEqual(fireAt, date(2026, 7, 6, 9, 0))
    }

    /// From a Monday, "next Monday" is 7 days away — never today.
    func testNextMonday_FromMonday_Is7DaysAway() {
        let monday = date(2026, 7, 6, 14, 0)
        let fireAt = RemindPreset.nextMonday9am.fireAt(now: monday, calendar: cal)
        XCTAssertEqual(fireAt, date(2026, 7, 13, 9, 0))
    }

    /// From a Sunday, "next Monday" is tomorrow.
    func testNextMonday_FromSunday_IsTomorrow() {
        let sunday = date(2026, 7, 5, 14, 0)
        let fireAt = RemindPreset.nextMonday9am.fireAt(now: sunday, calendar: cal)
        XCTAssertEqual(fireAt, date(2026, 7, 6, 9, 0))
    }

    /// From a Saturday, "next Monday" is 2 days.
    func testNextMonday_FromSaturday() {
        let saturday = date(2026, 7, 4, 14, 0)
        let fireAt = RemindPreset.nextMonday9am.fireAt(now: saturday, calendar: cal)
        XCTAssertEqual(fireAt, date(2026, 7, 6, 9, 0))
    }

    // MARK: - Custom

    func testCustom_ReturnsNil() {
        XCTAssertNil(RemindPreset.custom.fireAt(now: Date(), calendar: cal))
    }
}
