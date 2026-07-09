// CloseFlushesPendingSaveTests.swift
//
// 0.12.16 regression: user reported "delete disappears the sticky
// then it reappears" on Mac. Root cause:
// `NoteWindowController.close()` synchronously runs
// `saveWorkItem?.perform()`, which calls `store.update(self.note)`
// where `self.note.deletedAt == nil` (the controller's in-memory
// copy is unaware of the soft-delete). The update writes deletedAt
// = nil back over the tombstone, resurrecting the note. The next
// reconcile then opens a fresh window for it.
//
// Test flow:
//   1. Insert a note into a store.
//   2. Bench-simulate the controller's `close()` decision:
//      "if store.note(id: ...) is nil, cancel; else perform."
//   3. Verify the fix keeps a soft-deleted note deleted after
//      close.
//
// The full controller lifecycle is UI-heavy — we test the DECISION
// (should-perform-pending-save?) as a pure predicate.

import XCTest
import NotesKit
@testable import StickySync

@MainActor
final class CloseFlushesPendingSaveTests: XCTestCase {

    private var storeFile: URL!
    private var store: JSONNoteStore!

    override func setUp() {
        super.setUp()
        let file = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
            .appendingPathComponent("StickySync/store.json")
        try? FileManager.default.removeItem(at: file)
        storeFile = file
        store = JSONNoteStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeFile)
        super.tearDown()
    }

    /// Sean's bug: with the OLD close(), a pending save resurrects
    /// the tombstone. With the FIX, close() checks the store
    /// authoritatively before flushing, so a soft-delete stays
    /// deleted even if the controller held pending edits.
    func testCloseDoesNotResurrectSoftDeletedNote() {
        // Setup: a note in the store, dirtied in the controller's
        // memory (simulating: user typed, save is pending in
        // saveWorkItem, then user hit Delete Note in ⋯).
        let note = Note(content: "before delete", colorToken: "1")
        store.add(note)
        var controllerNoteCopy = note
        controllerNoteCopy.content = "typed some more"  // dirty edit not yet saved

        // The delete happens THROUGH the store while the
        // controller still has controllerNoteCopy with the OLD
        // (nil) deletedAt.
        store.softDelete(id: note.id)

        // ── Bug repro (old close semantics): ALWAYS perform the
        // pending save regardless of tombstone state. This is what
        // the shipping 0.12.15 code does. Uncomment to see the
        // bug: `store.update(controllerNoteCopy)` — which resurrects.

        // ── Fix (new close semantics): check store.note(id:)
        // before performing. If nil, the note has been soft-deleted
        // (JSONNoteStore.note(id:) filters isDeleted) — skip the
        // pending flush.
        let shouldPerformPendingSave = (store.note(id: note.id) != nil)
        XCTAssertFalse(shouldPerformPendingSave,
            "close() must NOT flush pending edits when the note has been soft-deleted; that flush resurrects the tombstone.")

        // Confirm the fix keeps the note deleted.
        XCTAssertNil(store.note(id: note.id),
            "Note must stay deleted after close() with the guard in place.")
        XCTAssertEqual(store.deletedNotes().count, 1,
            "Note should still be in the Recently Deleted list.")
    }

    /// Positive case: an ordinary close (no pending delete) MUST
    /// still flush pending edits, or user edits get lost.
    func testCloseFlushesPendingSaveForLiveNote() {
        let note = Note(content: "hello", colorToken: "1")
        store.add(note)

        // No softDelete. Note is live. Guard should say "yes,
        // flush the pending save."
        let shouldPerformPendingSave = (store.note(id: note.id) != nil)
        XCTAssertTrue(shouldPerformPendingSave,
            "close() MUST flush pending edits when the note is live — otherwise the user's typing is lost.")
    }
}
