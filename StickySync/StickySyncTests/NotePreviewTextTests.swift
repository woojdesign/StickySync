// NotePreviewTextTests.swift
//
// Pin the snippet rules across both code paths (one-line `snippet`
// and two-line `snippet2`). Sean's 0.7.24 report: a single-long-line
// sticky should fill the snippet area with the title's overflow
// remainder, instead of leaving the row half-empty.

import XCTest
import NotesKit
@testable import StickySync

final class NotePreviewTextTests: XCTestCase {

    // MARK: - snippet2 (iOS list rows)

    func testSnippet2_MultiLineNote_UsesLinesAfterTitle() {
        let note = Note(content: """
            Groceries
            - milk
            - eggs
            - bread
            """, colorToken: "1")
        let s = NotePreviewText.snippet2(for: note)
        XCTAssertEqual(s, "- milk\n- eggs",
                       "first two non-empty lines after the title, with a newline between")
    }

    func testSnippet2_SingleLongLine_UsesOverflowAsSnippet() {
        // The Sean-reported bug. Pre-fix this returned "" because there
        // was no line 2 — the row showed a truncated title and nothing
        // else even though the body still had content past the cutoff.
        let line = "buy milk eggs bread butter cheese yogurt apple banana blueberry oats granola cereal pasta tomato basil"
        XCTAssertGreaterThan(line.count, 60, "test fixture must overflow the title boundary")
        let note = Note(content: line, colorToken: "1")
        let s = NotePreviewText.snippet2(for: note)
        XCTAssertFalse(s.isEmpty, "single overflowing line should fill the snippet area")
        let expected = String(line.dropFirst(60))
        XCTAssertTrue(s.hasPrefix(String(expected.prefix(60))),
                      "snippet should begin where the title's 60-char truncation cut off")
    }

    func testSnippet2_SingleShortLine_StaysEmpty() {
        // Don't fabricate an overflow when the title fits cleanly; the
        // row should just show the title and let the snippet area
        // collapse.
        let note = Note(content: "buy milk", colorToken: "1")
        XCTAssertEqual(NotePreviewText.snippet2(for: note), "")
    }

    func testSnippet2_StripsHeadingMarker_SingleLine() {
        // The overflow path goes through the same cleanLineForPreview
        // helper as the multi-line path, so a leading `# ` is stripped.
        let line = "# " + String(repeating: "x", count: 100)
        let note = Note(content: line, colorToken: "1")
        let s = NotePreviewText.snippet2(for: note)
        XCTAssertFalse(s.contains("#"), "leading heading marker must be stripped before truncation")
    }

    // MARK: - snippet (one-line, used by Mac all-notes pre-card style)

    func testSnippet_OnlyTitle_ReturnsEmpty() {
        let note = Note(content: "Just a title", colorToken: "1")
        XCTAssertEqual(NotePreviewText.snippet(for: note), "")
    }

    func testSnippet_StripsLeadingHash() {
        // Regression for the 0.7.18 fix that added stripHeadingMarker to
        // the snippet path. A body whose second line is `## The bind`
        // should render as "The bind" in the snippet column.
        let note = Note(content: "Sync trust\n## The bind", colorToken: "1")
        XCTAssertEqual(NotePreviewText.snippet(for: note), "The bind")
    }
}
