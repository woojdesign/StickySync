import Foundation

/// The seam between the app and persistence.
///
/// The whole UI talks to this protocol and nothing else, so swapping the
/// backing store is a drop-in. Phase 1 ships `JSONNoteStore` (local,
/// single-user — perfect for that). Phase 2 adds a Core Data +
/// `NSPersistentCloudKitContainer` implementation behind this same protocol
/// to get cross-device sync, and the UI never changes.
///
/// `onChange` is how an external mutation (a sync pulling in a remote edit)
/// tells the UI to refresh. The local JSON store never fires it; the CloudKit
/// store will.
public protocol NoteStore: AnyObject {
    /// Non-deleted notes, oldest first.
    func allNotes() -> [Note]
    func note(id: UUID) -> Note?
    func layout(for id: UUID) -> NoteLayout?

    func add(_ note: Note)
    /// Persists a note and stamps `modifiedAt`.
    func update(_ note: Note)
    func setLayout(_ layout: NoteLayout)
    /// Soft delete: sets a tombstone instead of dropping the record.
    func softDelete(id: UUID)

    /// Fired when notes change from outside the app (e.g. an incoming sync).
    var onChange: (() -> Void)? { get set }
}

public extension NoteStore {
    /// Show/hide a note on THIS device (device-local; never synced) — used by
    /// "close" (hide) and reopening from the notes list. Distinct from
    /// `softDelete`, which tombstones the note and removes it everywhere.
    func setHidden(_ hidden: Bool, for id: UUID) {
        if var layout = layout(for: id) {
            layout.hidden = hidden
            setLayout(layout)
        } else {
            // No geometry yet: a zero-size sentinel; the window controller
            // cascades a fresh frame when it sees width/height == 0.
            setLayout(NoteLayout(noteID: id, x: 0, y: 0, width: 0, height: 0, hidden: hidden))
        }
    }

    /// Whether the note is currently closed (hidden) on this device.
    func isHidden(_ id: UUID) -> Bool {
        layout(for: id)?.hidden ?? false
    }
}
