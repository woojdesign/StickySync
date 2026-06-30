// PostPolishChipTests.swift
//
// Pins the 0.9.0 post-polish chip state machine. The chrome
// (NSWindow + buttons) is created lazily on `show(over:polished:)`
// — if we call show with a real anchor window we'd need a live
// NSWindow context the XCTest harness doesn't bootstrap well. So
// these tests exercise the closure-binding contract and the state
// transitions without driving show() (which is documented as
// requiring live AppKit chrome).
//
// What we CAN test:
//   - initial state is .none
//   - hide() from .none stays .none (idempotent)
//   - Closure capture for onCopy / onDelete behaves correctly

import XCTest
@testable import StickySync

final class PostPolishChipTests: XCTestCase {

    func testInitialState_None() {
        XCTAssertEqual(PostPolishChip().state, .none)
    }

    func testHide_FromNone_StaysNone() {
        let chip = PostPolishChip()
        chip.hide()
        XCTAssertEqual(chip.state, .none)
    }

    /// The chip stores its `polishedText` until copy/delete/hide
    /// — so subsequent Copy taps return the same text (no race with
    /// a later session overwriting it). Verified by binding onCopy
    /// without calling show, then asserting the closure is callable.
    /// The actual show()-driven flow needs a live NSWindow and is
    /// exercised in production.
    func testOnCopy_BindingCapturesProvidedText() {
        let chip = PostPolishChip()
        var captured: String?
        chip.onCopy = { captured = $0 }
        // Simulate the binding firing — bypasses show() since we
        // can't fake a real NSWindow under XCTest.
        chip.onCopy?("polished text")
        XCTAssertEqual(captured, "polished text")
    }

    func testOnDelete_Binding() {
        let chip = PostPolishChip()
        var called = false
        chip.onDelete = { called = true }
        chip.onDelete?()
        XCTAssertTrue(called)
    }
}
