import Foundation

/// Local, single-user store backed by one JSON file in Application Support.
///
/// It already keeps tombstones and timestamps, so the data model is
/// sync-ready — when Phase 2 swaps in a CloudKit-backed store, the shape of
/// the data doesn't change.
public final class JSONNoteStore: NoteStore {
    public var onChange: (() -> Void)?

    private struct Persisted: Codable {
        var notes: [Note]
        var layouts: [NoteLayout]
    }

    private var notesByID: [UUID: Note] = [:]
    private var layoutsByID: [UUID: NoteLayout] = [:]
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? JSONNoteStore.defaultFileURL()
        load()
    }

    public static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("StickySync", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    public func allNotes() -> [Note] {
        notesByID.values
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func note(id: UUID) -> Note? {
        guard let n = notesByID[id], !n.isDeleted else { return nil }
        return n
    }

    public func layout(for id: UUID) -> NoteLayout? { layoutsByID[id] }

    public func add(_ note: Note) {
        notesByID[note.id] = note
        save()
    }

    public func update(_ note: Note) {
        var updated = note
        updated.modifiedAt = Date()
        notesByID[note.id] = updated
        save()
    }

    public func setLayout(_ layout: NoteLayout) {
        layoutsByID[layout.noteID] = layout
        save()
    }

    public func softDelete(id: UUID) {
        guard var note = notesByID[id] else { return }
        let now = Date()
        note.deletedAt = now
        note.modifiedAt = now
        notesByID[id] = note
        save()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let persisted = try? JSONDecoder.stickySync.decode(Persisted.self, from: data)
        else { return }
        notesByID = Dictionary(persisted.notes.map { ($0.id, $0) }) { _, last in last }
        layoutsByID = Dictionary(persisted.layouts.map { ($0.noteID, $0) }) { _, last in last }
    }

    private func save() {
        let persisted = Persisted(notes: Array(notesByID.values),
                                  layouts: Array(layoutsByID.values))
        guard let data = try? JSONEncoder.stickySync.encode(persisted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var stickySync: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

private extension JSONDecoder {
    static var stickySync: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
