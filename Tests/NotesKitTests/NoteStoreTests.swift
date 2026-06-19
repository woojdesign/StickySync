import XCTest
@testable import NotesKit

/// Round-trip tests that run against both store implementations through the
/// shared `NoteStore` protocol — the same checks a sync store must also pass.
final class NoteStoreTests: XCTestCase {

    func testCloudKitStoreInMemoryRoundTrip() {
        // inMemory: plain Core Data, no CloudKit — proves the programmatic
        // model loads and CRUD works without entitlements.
        let store = CloudKitNoteStore(inMemory: true)
        runRoundTrip(on: store)
    }

    func testJSONStoreRoundTrip() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stickysync-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = JSONNoteStore(fileURL: tmp)
        runRoundTrip(on: store)
    }

    private func runRoundTrip(on store: NoteStore) {
        XCTAssertTrue(store.allNotes().isEmpty)

        let note = Note(content: "hello", colorToken: "sky", fontName: "rounded", fontSize: 18)
        store.add(note)

        let all = store.allNotes()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "hello")
        XCTAssertEqual(all.first?.colorToken, "sky")
        XCTAssertEqual(all.first?.fontName, "rounded")
        XCTAssertEqual(all.first?.fontSize, 18)

        var updated = note
        updated.content = "updated"
        store.update(updated)
        XCTAssertEqual(store.note(id: note.id)?.content, "updated")

        // Geometry is device-local but still persisted by the store.
        store.setLayout(NoteLayout(noteID: note.id, x: 10, y: 20, width: 240, height: 180))
        XCTAssertEqual(store.layout(for: note.id)?.width, 240)

        // Soft delete hides the note but keeps a tombstone.
        store.softDelete(id: note.id)
        XCTAssertTrue(store.allNotes().isEmpty)
        XCTAssertNil(store.note(id: note.id))
    }
}
