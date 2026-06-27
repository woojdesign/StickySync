// SyncRaceLWWTests.swift
//
// Pins the LWW gate used by NoteWindowController (Mac) and NoteEditorView
// (iOS) when deciding whether to apply a pending remote update at flush
// time. The dabi paste-image-loss bug existed because there was no such
// gate — a stale CloudKit refresh was held during typing, then flushed
// on focus-loss, wiping the user's just-pasted image.
//
// The gate is now: pending.modifiedAt > local.modifiedAt → apply,
// otherwise drop. This test pins both directions plus the
// equal-timestamps tie-breaker (don't apply — local wins on tie because
// the user's intent is what's already on screen).

import XCTest
import NotesKit

final class SyncRaceLWWTests: XCTestCase {

    private func note(id: UUID = UUID(), content: String, at instant: TimeInterval) -> Note {
        Note(id: id,
             content: content,
             colorToken: "1",
             fontName: "system",
             fontSize: 15,
             createdAt: Date(timeIntervalSince1970: 0),
             modifiedAt: Date(timeIntervalSince1970: instant))
    }

    func testRemoteIsNewer_Applies() {
        let id = UUID()
        let local  = note(id: id, content: "local edits",  at: 100)
        let remote = note(id: id, content: "remote newer", at: 200)
        XCTAssertTrue(remote.modifiedAt > local.modifiedAt,
                      "remote-newer must pass the gate so genuine cross-device updates are applied")
    }

    /// The dabi case: user pasted at T1, stale remote was held during
    /// typing, focus-loss flush should *not* apply the older pending —
    /// dropping it lets the next local save push our newer state up.
    func testRemoteIsOlder_DropsAtFlush() {
        let id = UUID()
        let local  = note(id: id, content: "![dabi](attachment://abc)", at: 200)
        let remote = note(id: id, content: "pre-paste content", at: 100)
        XCTAssertFalse(remote.modifiedAt > local.modifiedAt,
                       "remote-older must NOT pass the gate — applying it would wipe the local paste")
    }

    /// Equal-timestamp tie: local wins. The user is looking at the local
    /// version; replacing it with a coincidentally-same-modifiedAt remote
    /// would be a visible-but-unmotivated flicker.
    func testEqualTimestamps_DropsAtFlush() {
        let id = UUID()
        let local  = note(id: id, content: "same time A", at: 150)
        let remote = note(id: id, content: "same time B", at: 150)
        XCTAssertFalse(remote.modifiedAt > local.modifiedAt,
                       "equal-timestamps must NOT pass the gate — local intent wins on tie")
    }
}
