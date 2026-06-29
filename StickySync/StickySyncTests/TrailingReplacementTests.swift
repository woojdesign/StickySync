// TrailingReplacementTests.swift
//
// Pins the NoteWindowController.trailingReplacementRange policy that
// guards the WhisperKit polish swap (0.8.1). The polish path waits a
// beat after stop, then asks to replace the SFSpeech tail with the
// higher-accuracy WhisperKit text — but only when the SFSpeech text
// is still trailing. If the user typed past it (or sync replaced the
// content), we leave their edits alone.

import XCTest
@testable import StickySync

final class TrailingReplacementTests: XCTestCase {

    /// The happy path: content ends with the SFSpeech text → returns
    /// the range covering just the tail.
    func testTrailing_Matches_ReturnsTailRange() {
        let content = "earlier notes\nspoken transcript"
        let expected = "spoken transcript"
        let range = NoteWindowController.trailingReplacementRange(
            in: content, expected: expected)
        XCTAssertEqual(range, NSRange(location: 14, length: 17))
    }

    /// User typed after the SFSpeech text settled → no swap. This is
    /// the safeguard that protects user edits during the WhisperKit
    /// pass.
    func testTrailing_UserTypedPast_NoOp() {
        let content = "earlier\nspoken transcript and then user typed this"
        let expected = "spoken transcript"
        XCTAssertNil(NoteWindowController.trailingReplacementRange(
            in: content, expected: expected),
            "user typed past the SFSpeech text — polish swap must abort to preserve their edits")
    }

    /// Empty `expected` — defensive guard for a degenerate case
    /// (SFSpeech returned nothing, finalizer somehow asked to swap).
    /// Nothing to match, so nothing to do.
    func testTrailing_EmptyExpected_NoOp() {
        XCTAssertNil(NoteWindowController.trailingReplacementRange(
            in: "any content", expected: ""))
    }

    /// Content shorter than expected — can't possibly trail.
    func testTrailing_ContentShorterThanExpected_NoOp() {
        XCTAssertNil(NoteWindowController.trailingReplacementRange(
            in: "short", expected: "much longer expected text"))
    }

    /// Content == expected exactly — the whole content is the tail.
    /// Returns full range.
    func testTrailing_ContentEqualsExpected_FullRange() {
        let content = "exactly the speech text"
        let range = NoteWindowController.trailingReplacementRange(
            in: content, expected: content)
        XCTAssertEqual(range, NSRange(location: 0, length: 23))
    }

    /// Expected appears mid-content but NOT at the end — must NOT
    /// match. The function is specifically about *trailing* presence.
    func testTrailing_MatchesMidContent_NoOp() {
        let content = "spoken transcript followed by more text"
        let expected = "spoken transcript"
        XCTAssertNil(NoteWindowController.trailingReplacementRange(
            in: content, expected: expected))
    }
}
