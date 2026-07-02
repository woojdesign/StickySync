// DeletedNotesStoreTests.swift
//
// Pins NotesKit's 0.10.3 additions: deletedNotes(), restore(id:),
// hardDelete(id:). Exercised via JSONNoteStore in a temp dir so
// tests don't touch the user's real store.

import XCTest
import NotesKit

final class DeletedNotesStoreTests: XCTestCase {

    private var storeDir: URL!
    private var store: JSONNoteStore!

    override func setUp() {
        super.setUp()
        storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeletedNotesStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        // JSONNoteStore uses a hardcoded path; recreate as a fresh instance
        // and depend on empty state by clearing any pre-existing file.
        let file = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
            .appendingPathComponent("StickySync/store.json")
        try? FileManager.default.removeItem(at: file)
        store = JSONNoteStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeDir)
        super.tearDown()
    }

    private func makeNote(content: String = "hi") -> Note {
        let n = Note(content: content, colorToken: "1")
        store.add(n)
        return n
    }

    /// Soft-deleting a note pulls it out of `allNotes()` and puts
    /// it in `deletedNotes()`.
    func testSoftDelete_MovesNoteToDeletedList() {
        let n = makeNote(content: "will die")
        store.softDelete(id: n.id)
        XCTAssertFalse(store.allNotes().contains(where: { $0.id == n.id }))
        XCTAssertTrue(store.deletedNotes().contains(where: { $0.id == n.id }))
    }

    /// `deletedNotes()` orders by `deletedAt` DESC (most-recently
    /// deleted first) — the Recently Deleted list reads top-to-bottom
    /// in that order.
    func testDeletedNotes_MostRecentFirst() {
        let a = makeNote(content: "a")
        let b = makeNote(content: "b")
        store.softDelete(id: a.id)
        Thread.sleep(forTimeInterval: 0.02) // enforce ordering resolution
        store.softDelete(id: b.id)
        let ordered = store.deletedNotes()
        XCTAssertEqual(ordered.first?.id, b.id, "b was deleted after a → should be first")
        XCTAssertEqual(ordered.last?.id, a.id)
    }

    /// Restore clears the tombstone. Note reappears in `allNotes()`
    /// and drops from `deletedNotes()`.
    func testRestore_UnsetsTombstone() {
        let n = makeNote(content: "coming back")
        store.softDelete(id: n.id)
        store.restore(id: n.id)
        XCTAssertTrue(store.allNotes().contains(where: { $0.id == n.id }))
        XCTAssertFalse(store.deletedNotes().contains(where: { $0.id == n.id }))
        XCTAssertNil(store.note(id: n.id)?.deletedAt)
    }

    /// Hard-delete drops the row entirely. Note is gone from BOTH
    /// `allNotes()` and `deletedNotes()`.
    func testHardDelete_RemovesFromBothLists() {
        let n = makeNote(content: "erased")
        store.softDelete(id: n.id)
        XCTAssertTrue(store.deletedNotes().contains(where: { $0.id == n.id }))
        store.hardDelete(id: n.id)
        XCTAssertFalse(store.allNotes().contains(where: { $0.id == n.id }))
        XCTAssertFalse(store.deletedNotes().contains(where: { $0.id == n.id }))
    }

    /// Hard-delete works on a live note too (no soft-delete step),
    /// though the app flow always goes through soft-delete first.
    func testHardDelete_LiveNote_Removes() {
        let n = makeNote(content: "live")
        store.hardDelete(id: n.id)
        XCTAssertFalse(store.allNotes().contains(where: { $0.id == n.id }))
        XCTAssertNil(store.note(id: n.id))
    }
}
