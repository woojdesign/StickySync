// RecentlyDeletedPurge.swift
//
// 0.10.5: 30-day auto-purge for the Recently Deleted list. Runs on
// app launch (both platforms) — walks store.deletedNotes(), calls
// hardDelete on anything whose deletedAt is older than the retention
// cutoff.
//
// The retention value (30 days) matches every major app's Recently
// Deleted convention (Apple Notes / Photos / Files / Mail; Notion
// defaults to 30 for personal plans). No user-configurable setting
// — the calm-tools bar is "no cognitive load."
//
// Design: the expiration decision is a pure helper that takes
// (deleted notes, now) → [ids-to-purge]. That lets us pin the
// behavior in tests with time injection without touching a real
// store. The purge() entry point wires the helper to a live store.

import Foundation
import NotesKit

enum RecentlyDeletedPurge {
    /// 30 days in seconds.
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// Returns the IDs of soft-deleted notes whose `deletedAt` is
    /// older than `now - retention`. Callers hard-delete each one.
    ///
    /// Notes with a nil `deletedAt` are ignored — they aren't truly
    /// deleted (defensive: `deletedNotes()` shouldn't return them,
    /// but if the store ever returns a mixed list we don't want to
    /// hard-delete a live note by accident).
    static func expiredIDs(in deletedNotes: [Note],
                           now: Date,
                           retention: TimeInterval = retention) -> [UUID] {
        let cutoff = now.addingTimeInterval(-retention)
        return deletedNotes.compactMap { note in
            guard let deletedAt = note.deletedAt else { return nil }
            return deletedAt < cutoff ? note.id : nil
        }
    }

    /// Wire into a live store: fetch deleted notes, compute the
    /// expired set, hard-delete each. Called from AppDelegate on
    /// macOS launch and NotesModel.init on iOS.
    static func purge(store: NoteStore, now: Date = Date()) {
        let ids = expiredIDs(in: store.deletedNotes(), now: now)
        for id in ids { store.hardDelete(id: id) }
    }
}
