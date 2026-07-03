// QALaunchOptionsTests.swift
//
// 0.11.0: pins the flag parser. QALaunchOptions reads its state
// from `CommandLine.arguments`, so we can't inject args directly
// under XCTest — but we CAN test a pure `parse(_:)` helper. Adds
// that helper alongside the existing `fromCommandLine()` static.

import XCTest
@testable import StickySync

final class QALaunchOptionsTests: XCTestCase {

    func testParse_NoQAFlag_ReturnsNil() {
        XCTAssertNil(QALaunchOptions.parse(args: ["Foo", "--other"]))
    }

    func testParse_QAFlagAlone_ReturnsDefaults() {
        guard let opts = QALaunchOptions.parse(args: ["Foo", "--qa-sticky"]) else {
            return XCTFail("expected non-nil")
        }
        XCTAssertEqual(opts.colorSlot, 1)
        XCTAssertFalse(opts.chromeVisible)
        XCTAssertEqual(opts.frame, NSRect(x: 100, y: 100, width: 400, height: 300))
    }

    func testParse_Color_ClampedTo1Through7() {
        // Valid slot
        let ok = QALaunchOptions.parse(args: ["Foo", "--qa-sticky", "--qa-sticky-color", "5"])!
        XCTAssertEqual(ok.colorSlot, 5)
        // Out-of-range slot → falls back to default (1)
        let bad = QALaunchOptions.parse(args: ["Foo", "--qa-sticky", "--qa-sticky-color", "42"])!
        XCTAssertEqual(bad.colorSlot, 1)
    }

    func testParse_Text_Replaces() {
        let opts = QALaunchOptions.parse(args: ["Foo", "--qa-sticky",
                                                "--qa-sticky-text", "hello\nworld"])!
        XCTAssertEqual(opts.text, "hello\nworld")
    }

    func testParse_ChromeVisible_Flag() {
        let opts = QALaunchOptions.parse(args: ["Foo", "--qa-sticky",
                                                "--qa-chrome-visible"])!
        XCTAssertTrue(opts.chromeVisible)
    }

    func testParse_Frame_ParsedCorrectly() {
        let opts = QALaunchOptions.parse(args: ["Foo", "--qa-sticky",
                                                "--qa-frame", "50,60,700,800"])!
        XCTAssertEqual(opts.frame, NSRect(x: 50, y: 60, width: 700, height: 800))
    }

    /// A malformed `--qa-frame` value (wrong number of components,
    /// non-numeric) falls back to the default rather than crashing.
    func testParse_MalformedFrame_KeepsDefault() {
        let opts = QALaunchOptions.parse(args: ["Foo", "--qa-sticky",
                                                "--qa-frame", "50,60"])!
        XCTAssertEqual(opts.frame, NSRect(x: 100, y: 100, width: 400, height: 300))
    }
}
