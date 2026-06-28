// SyncReportTests.swift
//
// Pin the SyncReport.formatted() output shape so a future edit doesn't
// accidentally drop a section or change the section order in a way that
// breaks anyone parsing reports back into structured data. Also covers
// the two empty-state cases (no LWW events, no user text) since those
// are the most likely real-world report shape early in beta — a tester
// hits "Report" without typing anything, before the gate has fired.

import XCTest
@testable import StickySync

final class SyncReportTests: XCTestCase {

    private func fixedDate() -> Date {
        // 2026-06-28T18:42:15Z
        Date(timeIntervalSince1970: 1782664935)
    }

    func testFormatted_TypicalReport_ContainsAllSections() {
        let report = SyncReport(
            appVersion: "0.7.13 (146)",
            osVersion: "macOS 15.6.1",
            device: "MacBook Pro",
            generatedAt: fixedDate(),
            syncState: "harmony",
            lwwEvents: [
                "2026-06-28T18:21:14Z  refresh BDACD0FA: editing → stash, local=…176 remote=…234",
                "2026-06-28T18:21:18Z  save BDACD0FA: snapshot=…412",
                "2026-06-28T18:21:18Z  post-save BDACD0FA: drop-overtaken, local=…412 pending=…234",
            ],
            userText: "Added a note on my Mac at lunch.\nIt didn't show up on my phone.")
        let s = report.formatted()
        XCTAssertTrue(s.contains("StickySync Sync Issue Report"))
        XCTAssertTrue(s.contains("App:        0.7.13 (146)"))
        XCTAssertTrue(s.contains("Sync state: harmony"))
        XCTAssertTrue(s.contains("What I was doing:"))
        XCTAssertTrue(s.contains("  Added a note on my Mac at lunch."),
                      "user text must be indented for the section's shape")
        XCTAssertTrue(s.contains("  It didn't show up on my phone."),
                      "multi-line user text must indent every line")
        XCTAssertTrue(s.contains("LWW gate events (last 30 min):"))
        XCTAssertTrue(s.contains("  2026-06-28T18:21:14Z  refresh BDACD0FA:"))
    }

    func testFormatted_EmptyEvents_ShowsExplicitMessage() {
        // Common in early beta: nothing's tripped the gate yet, but the
        // tester still wants to report. The empty-state copy must be
        // explicit so the recipient knows the absence is legit (not a
        // truncated report).
        let report = SyncReport(
            appVersion: "0.7.13 (146)",
            osVersion: "iOS 26.0",
            device: "iPhone 17",
            generatedAt: fixedDate(),
            syncState: "harmony",
            lwwEvents: [],
            userText: "It feels slow.")
        let s = report.formatted()
        XCTAssertTrue(s.contains("(no LWW gate events in the last 30 minutes)"))
    }

    func testFormatted_EmptyUserText_ShowsExplicitMessage() {
        // Belt-and-braces: also explicit if the user sent the report
        // without typing anything (we can't stop them — better to show
        // "(no description provided)" than render an empty section).
        let report = SyncReport(
            appVersion: "0.7.13 (146)",
            osVersion: "iOS 26.0",
            device: "iPhone 17",
            generatedAt: fixedDate(),
            syncState: "syncing",
            lwwEvents: ["2026-06-28T18:21:14Z  save BDACD0FA: snapshot=…412"],
            userText: "")
        let s = report.formatted()
        XCTAssertTrue(s.contains("(no description provided)"))
    }
}
