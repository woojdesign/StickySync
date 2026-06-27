// MCPTools.swift
//
// The six tool definitions that an AI assistant can call to read, create,
// edit, and delete the user's stickies. Each tool dispatches to the same
// NoteStore the rest of the app uses, so a `create_note` call appears in
// open windows immediately (via the store's onChange / CloudKit-mirroring
// signals) — there is no separate "AI notes" surface.
//
// The tool surface is deliberately tight: no font / size control, no
// font menu, no layout. The model gets text + a color slot, that's it.
// Bigger surface means more ways for an AI to make a note that doesn't
// look like one of yours.

import Foundation
import NotesKit

/// Pure-logic dispatcher: takes the parsed tool name + arguments, runs
/// against an injected NoteStore, returns an MCP CallTool result. No
/// HTTP, no transport — testable directly.
@MainActor
final class MCPTools {
    private let store: NoteStore

    init(store: NoteStore) {
        self.store = store
    }

    // MARK: - Tool catalog

    static let definitions: [MCPToolDefinition] = [
        .init(
            name: "list_notes",
            description: "List the user's non-deleted stickies, newest first. Returns id, a short preview, the color slot, and modifiedAt for each. Use this to find an id before calling get_note / update_note / delete_note.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max stickies to return (default 50, max 500).")
                    ])
                ])
            ])
        ),
        .init(
            name: "get_note",
            description: "Read the full content of a sticky by id. The id comes from list_notes / search_notes.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string"),
                        "description": .string("Sticky UUID (from list_notes or search_notes).")
                    ])
                ]),
                "required": .array([.string("id")])
            ])
        ),
        .init(
            name: "search_notes",
            description: "Find stickies whose content contains the given substring (case-insensitive). Returns the same shape as list_notes.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Substring to match against the sticky's content.")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max stickies to return (default 50, max 500).")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        ),
        .init(
            name: "create_note",
            description: "Create a new sticky with the given content. Returns the new sticky's id. Color is optional — defaults to slot 1 (the yellow-ish 'butter' position).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("Sticky body (plain Markdown).")
                    ]),
                    "color_slot": .object([
                        "type": .string("string"),
                        "description": .string("Color slot 1..7. Same slot identifier across themes.")
                    ])
                ]),
                "required": .array([.string("content")])
            ])
        ),
        .init(
            name: "update_note",
            description: "Replace the content of an existing sticky. Use get_note first if you need to edit (not overwrite) the existing body.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string"),
                        "description": .string("Sticky UUID.")
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("New sticky body. Replaces the existing content in full.")
                    ])
                ]),
                "required": .array([.string("id"), .string("content")])
            ])
        ),
        .init(
            name: "delete_note",
            description: "Soft-delete a sticky. The note gets a tombstone so the delete syncs across devices; recovery would require a manual edit of the underlying store.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string"),
                        "description": .string("Sticky UUID to delete.")
                    ])
                ]),
                "required": .array([.string("id")])
            ])
        )
    ]

    // MARK: - Dispatch

    /// Run a tool call. Always returns an `MCPCallToolResult` — protocol
    /// errors (invalid arguments, missing sticky) come back as
    /// `isError: true` text results, not JSON-RPC errors, per the MCP
    /// convention. JSON-RPC errors are reserved for "your request was
    /// malformed at the protocol level."
    func dispatch(toolName: String, arguments: [String: Any]) -> MCPCallToolResult {
        switch toolName {
        case "list_notes":   return listNotes(arguments)
        case "get_note":     return getNote(arguments)
        case "search_notes": return searchNotes(arguments)
        case "create_note":  return createNote(arguments)
        case "update_note":  return updateNote(arguments)
        case "delete_note":  return deleteNote(arguments)
        default:
            return .error("Unknown tool: \(toolName)")
        }
    }

    // MARK: - Individual tools

    private func listNotes(_ args: [String: Any]) -> MCPCallToolResult {
        let limit = clampedLimit(args["limit"])
        let notes = store.allNotes()
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
        return .text(encodeJSON(notes.map(Self.previewFields)))
    }

    private func getNote(_ args: [String: Any]) -> MCPCallToolResult {
        guard let idString = args["id"] as? String, let id = UUID(uuidString: idString) else {
            return .error("`id` must be a valid sticky UUID.")
        }
        guard let note = store.note(id: id), !note.isDeleted else {
            return .error("No sticky with id \(idString).")
        }
        return .text(encodeJSON([
            "id": note.id.uuidString,
            "content": note.content,
            "color_slot": note.colorToken,
            "modified_at": ISO8601DateFormatter().string(from: note.modifiedAt),
            "created_at": ISO8601DateFormatter().string(from: note.createdAt)
        ]))
    }

    private func searchNotes(_ args: [String: Any]) -> MCPCallToolResult {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return .error("`query` must be a non-empty string.")
        }
        let limit = clampedLimit(args["limit"])
        let q = query.lowercased()
        let hits = store.allNotes()
            .filter { $0.content.lowercased().contains(q) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
        return .text(encodeJSON(hits.map(Self.previewFields)))
    }

    private func createNote(_ args: [String: Any]) -> MCPCallToolResult {
        guard let content = args["content"] as? String else {
            return .error("`content` is required.")
        }
        let token = (args["color_slot"] as? String).map(Palette.canonicalSlot(for:)) ?? Palette.defaultToken
        let note = Note(content: content, colorToken: token)
        store.add(note)
        return .text(encodeJSON([
            "id": note.id.uuidString,
            "color_slot": token,
            "modified_at": ISO8601DateFormatter().string(from: note.modifiedAt)
        ]))
    }

    private func updateNote(_ args: [String: Any]) -> MCPCallToolResult {
        guard let idString = args["id"] as? String, let id = UUID(uuidString: idString) else {
            return .error("`id` must be a valid sticky UUID.")
        }
        guard let content = args["content"] as? String else {
            return .error("`content` is required.")
        }
        guard var note = store.note(id: id), !note.isDeleted else {
            return .error("No sticky with id \(idString).")
        }
        note.content = content
        note.modifiedAt = Date()
        store.update(note)
        return .text(encodeJSON([
            "id": idString,
            "modified_at": ISO8601DateFormatter().string(from: note.modifiedAt)
        ]))
    }

    private func deleteNote(_ args: [String: Any]) -> MCPCallToolResult {
        guard let idString = args["id"] as? String, let id = UUID(uuidString: idString) else {
            return .error("`id` must be a valid sticky UUID.")
        }
        guard store.note(id: id) != nil else {
            return .error("No sticky with id \(idString).")
        }
        store.softDelete(id: id)
        return .text(encodeJSON(["id": idString, "deleted": true]))
    }

    // MARK: - Helpers

    private func clampedLimit(_ raw: Any?) -> Int {
        let n = (raw as? Int) ?? 50
        return max(1, min(500, n))
    }

    /// The shape returned by list / search — short enough to fit in an
    /// LLM context window for hundreds of notes; rich enough to pick one.
    private static func previewFields(_ note: Note) -> [String: Any] {
        let preview = String(note.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        return [
            "id": note.id.uuidString,
            "preview": preview,
            "color_slot": note.colorToken,
            "modified_at": ISO8601DateFormatter().string(from: note.modifiedAt)
        ]
    }

    private func encodeJSON(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
