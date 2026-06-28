import SwiftUI
import Combine
import NotesKit

/// Bridges NotesKit's callback-based `NoteStore` to SwiftUI. Owns the synced
/// CloudKit store and republishes the note list whenever it changes — whether
/// from a local edit here or an incoming change from another device.
@MainActor
final class NotesModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    /// IDs of notes that are currently shared (either outgoing shares from
    /// this user or incoming shares accepted from someone else). Recomputed
    /// on every reload by asking the store. Empty for the JSON store.
    @Published private(set) var sharedNoteIDs: Set<UUID> = []
    /// Bumps on every `reload()` — including reloads triggered by attachment
    /// imports that don't change any visible note field. NoteCard's task
    /// includes this in its id so a thumb-bearing attachment arriving after
    /// its parent note re-fires the cover lookup. Without this, an
    /// attachment landing seconds after its note left the card thumbless
    /// until the user took some other action.
    @Published private(set) var dataTick: UInt64 = 0
    private let store: NoteStore

    /// The one shared store, exposed so the capture surface writes through the
    /// same container (a second NoteStore would mean two CloudKit containers).
    var sharedStore: NoteStore { store }

    init(store: NoteStore) {
        self.store = store
        reload()
        store.onChange = { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        // allNotes() already excludes soft-deleted tombstones, newest sorting
        // handled below so freshly-edited notes float to the top.
        notes = store.allNotes().sorted { $0.modifiedAt > $1.modifiedAt }
        sharedNoteIDs = Self.computeSharedNoteIDs(in: notes, store: store)
        dataTick &+= 1
    }

    private static func computeSharedNoteIDs(in notes: [Note], store: NoteStore) -> Set<UUID> {
        guard let ck = store as? CloudKitNoteStore else { return [] }
        var ids: Set<UUID> = []
        for n in notes where ck.isShared(n) { ids.insert(n.id) }
        return ids
    }

    @discardableResult
    func newNote() -> Note {
        var note = Note()
        note.fontName = "serif"   // wooj reading (Charter) by default for new notes
        store.add(note)
        reload()
        return note
    }

    func save(_ note: Note) {
        store.update(note)
        reload()
    }

    func delete(_ note: Note) {
        store.softDelete(id: note.id)
        reload()
    }
}
