// RecentlyDeletedIntegrationTests.swift
//
// Pins the iOS 0.10.4 integration: soft-deletes coming through
// NotesModel.delete surface into store.deletedNotes(), restore
// round-trips back into model.notes, and hardDelete removes
// permanently.
//
// The RecentlyDeletedView itself is a thin SwiftUI wrapper around
// these store calls; the value of these tests is the connective
// tissue (model → store → view), not the SwiftUI rendering.

import XCTest
import NotesKit
@testable import StickySyncMobile

@MainActor
final class RecentlyDeletedIntegrationTests: XCTestCase {

    private var model: NotesModel!
    private var store: JSONNoteStore!

    override func setUp() {
        super.setUp()
        // Reset the JSON store file so tests start from empty state.
        let file = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
            .appendingPathComponent("StickySync/store.json")
        try? FileManager.default.removeItem(at: file)
        store = JSONNoteStore()
        model = NotesModel(store: store)
    }

    private func makeNote(content: String) -> Note {
        var n = model.newNote()
        n.content = content
        model.save(n)
        return n
    }

    /// Delete via NotesModel (the iOS editor's exit path) surfaces the
    /// note into `store.deletedNotes()` — which is what
    /// RecentlyDeletedView reads.
    func testModelDelete_ShowsUpInDeletedNotes() {
        let n = makeNote(content: "toss me")
        model.delete(n)
        XCTAssertFalse(model.notes.contains(where: { $0.id == n.id }))
        XCTAssertTrue(store.deletedNotes().contains(where: { $0.id == n.id }))
    }

    /// Restore round-trips: deleted note leaves `deletedNotes()`,
    /// re-enters `model.notes` after `model.reload()`.
    func testRestore_RoundTrip() {
        let n = makeNote(content: "back from the dead")
        model.delete(n)
        store.restore(id: n.id)
        model.reload()
        XCTAssertTrue(model.notes.contains(where: { $0.id == n.id }))
        XCTAssertFalse(store.deletedNotes().contains(where: { $0.id == n.id }))
    }

    /// Permanent delete drops the row entirely — gone from both lists.
    func testHardDelete_RemovesEverywhere() {
        let n = makeNote(content: "erased")
        model.delete(n)
        store.hardDelete(id: n.id)
        XCTAssertFalse(store.deletedNotes().contains(where: { $0.id == n.id }))
        XCTAssertNil(store.note(id: n.id))
    }

    /// Empty-trash flow: hardDelete every deleted note. Repeated on
    /// each row so a single failure doesn't leave orphans.
    func testEmptyTrash_ClearsAllDeleted() {
        for i in 0..<3 {
            let n = makeNote(content: "note \(i)")
            model.delete(n)
        }
        XCTAssertEqual(store.deletedNotes().count, 3)
        for n in store.deletedNotes() {
            store.hardDelete(id: n.id)
        }
        XCTAssertTrue(store.deletedNotes().isEmpty)
    }
}
