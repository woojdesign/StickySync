// ReminderNotifierPreviewTests.swift
//
// 0.12.3: pin the pure notification-body formatter. Full notifier
// flow needs a real UNUserNotificationCenter + entitlement grant,
// which XCTest can't drive; the preview helper is a static
// function we can test in isolation.

import XCTest
@testable import StickySync

final class ReminderNotifierPreviewTests: XCTestCase {

    func testEmptyContent_FallbackString() {
        XCTAssertEqual(ReminderNotifier.previewBody(from: ""), "Tap to open.")
    }

    func testWhitespaceOnly_FallbackString() {
        XCTAssertEqual(ReminderNotifier.previewBody(from: "   \n \n"), "Tap to open.")
    }

    func testSingleLine_ShortEnough_ReturnedAsIs() {
        XCTAssertEqual(ReminderNotifier.previewBody(from: "buy milk"), "buy milk")
    }

    func testMultiLine_FirstLineOnly() {
        let content = "buy milk\nsecond line\nthird"
        XCTAssertEqual(ReminderNotifier.previewBody(from: content), "buy milk")
    }

    /// Long single line gets truncated at ~80 chars with ellipsis.
    func testLongSingleLine_TruncatedWithEllipsis() {
        let content = String(repeating: "a", count: 120)
        let body = ReminderNotifier.previewBody(from: content)
        XCTAssertEqual(body.count, 81, "80 chars + 1 ellipsis")
        XCTAssertTrue(body.hasSuffix("…"))
    }

    /// Leading whitespace on the first line is trimmed.
    func testLeadingWhitespaceTrimmed() {
        XCTAssertEqual(ReminderNotifier.previewBody(from: "   hello"), "hello")
    }
}
