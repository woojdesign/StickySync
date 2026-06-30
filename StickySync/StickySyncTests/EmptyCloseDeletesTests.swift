// EmptyCloseDeletesTests.swift
//
// Pins the 0.8.10 policy: ✕ on an empty sticky soft-deletes; ✕ on
// a sticky with content hides. The decision logic is a pure
// whitespace-trim check; testing it that way avoids needing to
// stand up AppDelegate's full controller graph.

import XCTest
@testable import StickySync

final class EmptyCloseDeletesTests: XCTestCase {

    /// Mirror of AppDelegate.handleRequestClose's decision logic.
    /// Returns true if the content qualifies as "empty enough to
    /// soft-delete on close" rather than just hide.
    private func shouldDeleteOnClose(_ content: String) -> Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func testEmptyString_DeletesOnClose() {
        XCTAssertTrue(shouldDeleteOnClose(""))
    }

    func testWhitespaceOnly_DeletesOnClose() {
        XCTAssertTrue(shouldDeleteOnClose("   "))
        XCTAssertTrue(shouldDeleteOnClose("\n\n"))
        XCTAssertTrue(shouldDeleteOnClose(" \t\n "))
    }

    func testRealContent_HidesOnClose() {
        XCTAssertFalse(shouldDeleteOnClose("a"))
        XCTAssertFalse(shouldDeleteOnClose("anything at all"))
    }

    /// Trailing whitespace doesn't count as content — the user
    /// hasn't typed anything meaningful. Sticky should be deleted.
    func testTrailingWhitespaceAroundEmpty_DeletesOnClose() {
        XCTAssertTrue(shouldDeleteOnClose("\n   \t  \n\n"))
    }

    /// A note with content surrounded by whitespace is real
    /// content. Hide, don't delete.
    func testContentSurroundedByWhitespace_HidesOnClose() {
        XCTAssertFalse(shouldDeleteOnClose("  hello  "))
    }
}
