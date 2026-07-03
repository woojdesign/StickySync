// RecentlyDeletedPurgeTests.swift
//
// 0.10.5: pins the auto-purge contract. The pure helper
// `expiredIDs(in:now:retention:)` is time-injected, so we can
// simulate 60 days from now without waiting a month. The purge()
// wrapper is verified through the JSON store.

import XCTest
import NotesKit
@testable import StickySync

final class RecentlyDeletedPurgeTests: XCTestCase {

    private let day: TimeInterval = 24 * 60 * 60

    private func deletedNote(id: UUID = UUID(), deletedAt: Date) -> Note {
        var n = Note(id: id, content: "x", colorToken: "1")
        n.deletedAt = deletedAt
        return n
    }

    // MARK: - Pure helper

    /// A note deleted 29 days ago is inside the 30-day window —
    /// stays.
    func testExpiredIDs_29DaysOld_NotExpired() {
        let now = Date()
        let n = deletedNote(deletedAt: now.addingTimeInterval(-29 * day))
        XCTAssertTrue(RecentlyDeletedPurge.expiredIDs(in: [n], now: now).isEmpty)
    }

    /// A note deleted 31 days ago is past the cutoff — purged.
    func testExpiredIDs_31DaysOld_Expired() {
        let now = Date()
        let n = deletedNote(deletedAt: now.addingTimeInterval(-31 * day))
        XCTAssertEqual(RecentlyDeletedPurge.expiredIDs(in: [n], now: now), [n.id])
    }

    /// The cutoff is inclusive-on-fresh-side: exactly 30 days
    /// old should be gone (< cutoff, not <=). We use `<` in the
    /// helper — this pins that.
    func testExpiredIDs_ExactlyAtCutoff_Expires() {
        let now = Date()
        let n = deletedNote(deletedAt: now.addingTimeInterval(-30 * day - 1))
        XCTAssertEqual(RecentlyDeletedPurge.expiredIDs(in: [n], now: now), [n.id])
    }

    /// Multi-note: mixed ages return only the expired IDs.
    func testExpiredIDs_MultipleAges_ReturnsOnlyOld() {
        let now = Date()
        let fresh = deletedNote(deletedAt: now.addingTimeInterval(-1 * day))
        let stale1 = deletedNote(deletedAt: now.addingTimeInterval(-45 * day))
        let stale2 = deletedNote(deletedAt: now.addingTimeInterval(-90 * day))
        let ids = Set(RecentlyDeletedPurge.expiredIDs(in: [fresh, stale1, stale2], now: now))
        XCTAssertEqual(ids, [stale1.id, stale2.id])
    }

    /// Defensive: a note with `deletedAt == nil` is never returned,
    /// even if it shows up in the input (in practice deletedNotes()
    /// filters it out — but if the store ever leaks a live note, we
    /// don't want to hard-delete it).
    func testExpiredIDs_NilDeletedAt_Ignored() {
        let now = Date()
        var live = Note(id: UUID(), content: "alive", colorToken: "1")
        live.deletedAt = nil
        XCTAssertTrue(RecentlyDeletedPurge.expiredIDs(in: [live], now: now).isEmpty)
    }

    /// Configurable retention — for tests that want to run against
    /// a different window (e.g., a "purge everything now" sweep).
    func testExpiredIDs_CustomRetention() {
        let now = Date()
        let n = deletedNote(deletedAt: now.addingTimeInterval(-5 * day))
        let expired = RecentlyDeletedPurge.expiredIDs(in: [n], now: now, retention: 3 * day)
        XCTAssertEqual(expired, [n.id])
    }

    // MARK: - Live-store wire

    /// End-to-end via JSONNoteStore: an old soft-deleted note is
    /// gone after purge; a fresh one survives.
    func testPurge_Store_RemovesOldOnly() {
        // Fresh store so we control state.
        let file = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
            .appendingPathComponent("StickySync/store.json")
        try? FileManager.default.removeItem(at: file)
        let store = JSONNoteStore()

        let fresh = Note(content: "keep", colorToken: "1")
        let stale = Note(content: "gone", colorToken: "1")
        store.add(fresh); store.add(stale)
        store.softDelete(id: fresh.id)
        store.softDelete(id: stale.id)

        // Rewrite stale's deletedAt to 60 days ago via restore+update.
        var staleUpdated = store.note(id: stale.id) ?? {
            // note(id:) filters deleted → fetch from the deleted list.
            store.deletedNotes().first { $0.id == stale.id }!
        }()
        staleUpdated.deletedAt = Date().addingTimeInterval(-60 * day)
        store.update(staleUpdated)

        RecentlyDeletedPurge.purge(store: store)

        // stale should be gone, fresh should still be in deletedNotes().
        XCTAssertFalse(store.deletedNotes().contains(where: { $0.id == stale.id }))
        XCTAssertTrue(store.deletedNotes().contains(where: { $0.id == fresh.id }))
    }
}
