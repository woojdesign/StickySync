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
