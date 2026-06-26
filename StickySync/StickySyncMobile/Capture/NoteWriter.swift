import Foundation
import NotesKit

/// Writes captured text into the shared NotesKit store, so it appears in
/// StickySync (and on every device) automatically. One calm default color, no
/// decisions at capture time.
final class NoteWriter {
    private let store: NoteStore

    /// Defaults to the CloudKit-backed store on StickySync's container, so
    /// captured notes land in StickySync. When iCloud is signed out it persists
    /// locally via Core Data and syncs once the account returns.
    init(store: NoteStore = CloudKitNoteStore(containerIdentifier: "iCloud.design.wooj.StickySync")) {
        self.store = store
    }

    /// Creates a default-colored sticky from `text`. Returns the note, or nil
    /// if the text is empty — Capture never creates empty notes.
    @discardableResult
    func write(_ text: String) -> Note? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Slot 1 is the canonical yellow-ish in every theme; the user can
        // recolor in the editor.
        let note = Note(content: trimmed, colorToken: Palette.defaultToken)
        store.add(note)
        return note
    }

    /// Replaces a note's body — used when the WhisperKit final pass refines the
    /// text after the note has already been written (Phase 3).
    func update(_ note: Note, content: String) {
        var updated = note
        updated.content = content
        store.update(updated)
    }

    /// Replaces a note's color — used when the user taps a swatch on the
    /// SavedView before the polish + dismiss cycle completes.
    func update(_ note: Note, colorToken: String) {
        var updated = note
        updated.colorToken = colorToken
        store.update(updated)
    }
}
