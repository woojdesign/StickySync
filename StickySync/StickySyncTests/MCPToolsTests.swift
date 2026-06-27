// MCPToolsTests.swift
//
// Tests for the AI-access tool surface. Per the testing discipline:
// these pin every tool's request → response shape so an AI client
// that depends on the schema isn't silently broken by an internal
// refactor.
//
// Each test runs against an in-memory CloudKitNoteStore — no CloudKit
// roundtrip, but the same code path the app uses in production.

import XCTest
import NotesKit
@testable import StickySync

@MainActor
final class MCPToolsTests: XCTestCase {

    private var store: CloudKitNoteStore!
    private var tools: MCPTools!

    override func setUp() async throws {
        try await super.setUp()
        store = CloudKitNoteStore(inMemory: true)
        tools = MCPTools(store: store)
    }

    // MARK: - list_notes

    func testListNotes_EmptyStore_ReturnsEmptyArray() {
        let result = tools.dispatch(toolName: "list_notes", arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(decodeArray(result).isEmpty)
    }

    func testListNotes_NewestFirst() {
        store.add(Note(content: "old",  colorToken: "1", modifiedAt: Date(timeIntervalSince1970: 100)))
        store.add(Note(content: "new",  colorToken: "1", modifiedAt: Date(timeIntervalSince1970: 200)))
        store.add(Note(content: "mid",  colorToken: "1", modifiedAt: Date(timeIntervalSince1970: 150)))

        let items = decodeArray(tools.dispatch(toolName: "list_notes", arguments: [:]))
        XCTAssertEqual(items.map { $0["preview"] as? String }, ["new", "mid", "old"])
    }

    func testListNotes_RespectsLimit() {
        for i in 0..<10 {
            store.add(Note(content: "n\(i)", colorToken: "1"))
        }
        let items = decodeArray(tools.dispatch(toolName: "list_notes", arguments: ["limit": 3]))
        XCTAssertEqual(items.count, 3)
    }

    func testListNotes_ExcludesSoftDeleted() {
        store.add(Note(content: "kept",    colorToken: "1"))
        let goner = Note(content: "tombstoned", colorToken: "1")
        store.add(goner)
        store.softDelete(id: goner.id)

        let items = decodeArray(tools.dispatch(toolName: "list_notes", arguments: [:]))
        XCTAssertEqual(items.map { $0["preview"] as? String }, ["kept"])
    }

    // MARK: - get_note

    func testGetNote_RoundTripsContent() {
        let note = Note(content: "the answer is 42", colorToken: "3")
        store.add(note)

        let result = tools.dispatch(toolName: "get_note",
                                    arguments: ["id": note.id.uuidString])
        XCTAssertFalse(result.isError)
        let obj = decodeObject(result)
        XCTAssertEqual(obj["content"] as? String, "the answer is 42")
        XCTAssertEqual(obj["color_slot"] as? String, "3")
    }

    func testGetNote_MissingID_ReturnsErrorContent() {
        let result = tools.dispatch(toolName: "get_note",
                                    arguments: ["id": "not-a-uuid"])
        XCTAssertTrue(result.isError)
    }

    func testGetNote_DeletedNoteIsHidden() {
        let note = Note(content: "ghost", colorToken: "1")
        store.add(note)
        store.softDelete(id: note.id)

        let result = tools.dispatch(toolName: "get_note",
                                    arguments: ["id": note.id.uuidString])
        XCTAssertTrue(result.isError)
    }

    // MARK: - search_notes

    func testSearchNotes_SubstringCaseInsensitive() {
        store.add(Note(content: "buy MILK at the store", colorToken: "1"))
        store.add(Note(content: "call mom",              colorToken: "1"))
        store.add(Note(content: "milk frother",          colorToken: "1"))

        let items = decodeArray(tools.dispatch(toolName: "search_notes",
                                               arguments: ["query": "milk"]))
        XCTAssertEqual(items.count, 2)
    }

    func testSearchNotes_EmptyQueryReturnsError() {
        let result = tools.dispatch(toolName: "search_notes", arguments: ["query": ""])
        XCTAssertTrue(result.isError)
    }

    // MARK: - create_note

    func testCreateNote_DefaultsToSlotOne() {
        let result = tools.dispatch(toolName: "create_note",
                                    arguments: ["content": "fresh idea"])
        XCTAssertFalse(result.isError)
        let obj = decodeObject(result)
        XCTAssertEqual(obj["color_slot"] as? String, "1")
        XCTAssertEqual(store.allNotes().count, 1)
        XCTAssertEqual(store.allNotes().first?.content, "fresh idea")
    }

    func testCreateNote_AcceptsColorSlot() {
        let result = tools.dispatch(toolName: "create_note",
                                    arguments: ["content": "spicy", "color_slot": "3"])
        let obj = decodeObject(result)
        XCTAssertEqual(obj["color_slot"] as? String, "3")
        XCTAssertEqual(store.allNotes().first?.colorToken, "3")
    }

    func testCreateNote_LegacyColorNameMapsToSlot() {
        // An AI that knows about the historical "butter" / "rose" tokens
        // should still get the right slot — the canonicalSlot mapping
        // shouldn't bite us here.
        let result = tools.dispatch(toolName: "create_note",
                                    arguments: ["content": "old name", "color_slot": "rose"])
        let obj = decodeObject(result)
        XCTAssertEqual(obj["color_slot"] as? String, "3")
    }

    func testCreateNote_MissingContentIsError() {
        let result = tools.dispatch(toolName: "create_note", arguments: [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(store.allNotes().isEmpty)
    }

    // MARK: - update_note

    func testUpdateNote_ReplacesContent() {
        let note = Note(content: "before", colorToken: "1")
        store.add(note)

        let result = tools.dispatch(toolName: "update_note",
                                    arguments: ["id": note.id.uuidString, "content": "after"])
        XCTAssertFalse(result.isError)
        XCTAssertEqual(store.note(id: note.id)?.content, "after")
    }

    func testUpdateNote_BumpsModifiedAt() {
        let note = Note(content: "original",
                         colorToken: "1",
                         modifiedAt: Date(timeIntervalSinceNow: -3600))
        store.add(note)
        let oldModified = note.modifiedAt

        _ = tools.dispatch(toolName: "update_note",
                           arguments: ["id": note.id.uuidString, "content": "edited"])

        let updated = store.note(id: note.id)!
        XCTAssertGreaterThan(updated.modifiedAt, oldModified)
    }

    func testUpdateNote_RejectsUnknownID() {
        let result = tools.dispatch(toolName: "update_note",
                                    arguments: ["id": UUID().uuidString, "content": "huh"])
        XCTAssertTrue(result.isError)
    }

    // MARK: - delete_note

    func testDeleteNote_SoftDeletes() {
        let note = Note(content: "soon to be gone", colorToken: "1")
        store.add(note)

        let result = tools.dispatch(toolName: "delete_note",
                                    arguments: ["id": note.id.uuidString])
        XCTAssertFalse(result.isError)
        XCTAssertNil(store.note(id: note.id))   // hidden behind the tombstone filter
    }

    func testDeleteNote_RejectsUnknownID() {
        let result = tools.dispatch(toolName: "delete_note",
                                    arguments: ["id": UUID().uuidString])
        XCTAssertTrue(result.isError)
    }

    // MARK: - Tool catalog shape

    func testToolDefinitions_NamesMatchDispatchTable() {
        // Stops the catalog drifting away from the dispatcher — if a tool
        // is added to one but not the other, this test catches it.
        let knownNames = Set(["list_notes", "get_note", "search_notes",
                              "create_note", "update_note", "delete_note"])
        let definitionNames = Set(MCPTools.definitions.map(\.name))
        XCTAssertEqual(definitionNames, knownNames)
    }

    func testUnknownTool_ReturnsErrorContent() {
        let result = tools.dispatch(toolName: "drop_database", arguments: [:])
        XCTAssertTrue(result.isError)
    }

    // MARK: - Helpers

    private func decodeArray(_ result: MCPCallToolResult) -> [[String: Any]] {
        guard let text = result.content.first?.text,
              let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr
    }

    private func decodeObject(_ result: MCPCallToolResult) -> [String: Any] {
        guard let text = result.content.first?.text,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }
}
