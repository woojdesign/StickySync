import SwiftUI
import Combine
import NotesKit

/// Bridges NotesKit's callback-based `NoteStore` to SwiftUI. Owns the synced
/// CloudKit store and republishes the note list whenever it changes — whether
/// from a local edit here or an incoming change from another device.
@MainActor
final class NotesModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
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
