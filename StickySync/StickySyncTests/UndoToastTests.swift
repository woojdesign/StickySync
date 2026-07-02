// UndoToastTests.swift
//
// Pins the 0.10.0 UndoToast state machine. The window chrome is
// created lazily on `show(anchorFrame:)` — mirrors PostPolishChip's
// approach — so these tests exercise the closure-binding contract
// and state transitions without driving show() (which needs a live
// NSWindow context that XCTest doesn't bootstrap).

import XCTest
@testable import StickySync

final class UndoToastTests: XCTestCase {

    func testInitialState_None() {
        XCTAssertEqual(UndoToast().state, .none)
    }

    func testHide_FromNone_StaysNone() {
        let toast = UndoToast()
        toast.hide()
        XCTAssertEqual(toast.state, .none)
    }

    /// Undo binding fires the caller-provided closure.
    func testOnUndo_Binding() {
        let toast = UndoToast()
        var called = false
        toast.onUndo = { called = true }
        toast.onUndo?()
        XCTAssertTrue(called)
    }
}
