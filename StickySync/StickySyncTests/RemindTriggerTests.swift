// RemindTriggerTests.swift
//
// 0.12.1: pins the /remind detector — line-start match,
// case-insensitive, word-boundary requirement, correct strip range.

import XCTest
@testable import StickySync

final class RemindTriggerTests: XCTestCase {

    // MARK: - Positive matches

    /// Bare "/remind" alone on a line fires with an empty free-text.
    func testBareRemind_Fires_EmptyFreeText() {
        let text = "/remind"
        let m = RemindTrigger.detect(in: text, at: text.count)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.freeText, "")
    }

    /// "/remind tomorrow 9am" fires with the free-text captured.
    func testWithFreeText_FiresAndCaptures() {
        let text = "/remind tomorrow 9am"
        let m = RemindTrigger.detect(in: text, at: text.count)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.freeText, "tomorrow 9am")
    }

    /// Case-insensitive: "/Remind" and "/REMIND" both work.
    func testCaseInsensitive() {
        for variant in ["/Remind", "/REMIND", "/rEmInD tomorrow"] {
            XCTAssertNotNil(RemindTrigger.detect(in: variant, at: variant.count),
                            "should fire on: \(variant)")
        }
    }

    /// Leading whitespace on the line is fine — indent-then-slash.
    func testLeadingWhitespace_Fires() {
        let text = "   /remind in 30 min"
        let m = RemindTrigger.detect(in: text, at: text.count)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.freeText, "in 30 min")
    }

    /// Multi-line: the /remind must be on the cursor's own line;
    /// the strip range covers just that line (including the \n if
    /// there is one) — never eats the preceding line.
    func testMultiLine_StripRange_JustTheTriggerLine() {
        let text = "buy milk\n/remind tomorrow\nother note"
        let cursor = (text as NSString).range(of: "/remind tomorrow").location + 1
        guard let m = RemindTrigger.detect(in: text, at: cursor) else {
            return XCTFail("expected trigger")
        }
        let stripped = (text as NSString).substring(with: m.lineRangeToStrip)
        XCTAssertEqual(stripped, "/remind tomorrow\n")
    }

    // MARK: - Negative matches

    /// "/reminder" (no separator) should NOT fire — word boundary
    /// matters.
    func testNoSeparator_DoesNotFire() {
        for text in ["/reminder", "/remindME", "/remind-me"] {
            XCTAssertNil(RemindTrigger.detect(in: text, at: text.count),
                         "should NOT fire on: \(text)")
        }
    }

    /// Mid-word `/remind` — the cursor's on a line that contains
    /// `/remind` but not as the first token — should NOT fire.
    func testMidLine_DoesNotFire() {
        let text = "look up /remind syntax later"
        XCTAssertNil(RemindTrigger.detect(in: text, at: text.count))
    }

    /// URL-embedded `/remind` should NOT fire.
    func testInsideURL_DoesNotFire() {
        let text = "see docs at example.com/remind for info"
        XCTAssertNil(RemindTrigger.detect(in: text, at: text.count))
    }

    /// Empty input.
    func testEmptyText_ReturnsNil() {
        XCTAssertNil(RemindTrigger.detect(in: "", at: 0))
    }

    /// Cursor out of bounds — defensive.
    func testOutOfBoundsCursor_ReturnsNil() {
        XCTAssertNil(RemindTrigger.detect(in: "/remind", at: -5))
        XCTAssertNil(RemindTrigger.detect(in: "/remind", at: 9999))
    }

    /// A note that just says "/rem" (partial) should NOT fire.
    func testPartial_DoesNotFire() {
        let text = "/rem"
        XCTAssertNil(RemindTrigger.detect(in: text, at: text.count))
    }
}
