// MCPServerSmokeTests.swift
//
// HTTP-level smoke test: brings up the actual MCPServer on an ephemeral
// port, sends real JSON-RPC requests through URLSession, asserts the
// envelope shape + that a create→list round-trip mutates the store.
//
// This catches the bugs the unit tests can't — HTTP parsing,
// content-length handling, auth header enforcement, the JSON-RPC
// envelope structure. If the bytes-on-the-wire contract drifts, every
// AI client on the user's machine breaks; this test pins it.

import XCTest
import Network
import NotesKit
@testable import StickySync

@MainActor
final class MCPServerSmokeTests: XCTestCase {

    private var store: CloudKitNoteStore!
    private var server: MCPServer!
    private var token: String!
    private var port: NWEndpoint.Port!

    override func setUp() async throws {
        try await super.setUp()
        store = CloudKitNoteStore(inMemory: true)
        token = "test-token-\(UUID().uuidString)"
        // Pick a high random port so parallel test runs don't clash.
        let raw = UInt16.random(in: 49152...65000)
        port = NWEndpoint.Port(integerLiteral: raw)
        server = MCPServer(store: store, port: port, authToken: token)
        try server.start()
    }

    override func tearDown() async throws {
        server?.stop()
        try await super.tearDown()
    }

    // MARK: - Smoke

    func testInitialize_ReturnsServerInfo() async throws {
        let response = try await post("""
            { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {} }
            """)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let info = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(info["name"] as? String, "StickySync")
    }

    func testToolsList_IncludesAllSix() async throws {
        let response = try await post("""
            { "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {} }
            """)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertEqual(names, ["list_notes", "get_note", "search_notes",
                               "create_note", "update_note", "delete_note"])
    }

    func testCreateThenList_RoundTripThroughHTTP() async throws {
        _ = try await post("""
            { "jsonrpc": "2.0", "id": 3, "method": "tools/call",
              "params": {
                "name": "create_note",
                "arguments": { "content": "round trip through HTTP" }
              } }
            """)

        let listResp = try await post("""
            { "jsonrpc": "2.0", "id": 4, "method": "tools/call",
              "params": { "name": "list_notes", "arguments": {} } }
            """)
        let result = try XCTUnwrap(listResp["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        XCTAssertTrue(text.contains("round trip through HTTP"))
        XCTAssertEqual(store.allNotes().count, 1)
    }

    func testMissingAuthHeader_Is401() async throws {
        let url = URL(string: "http://127.0.0.1:\(port.rawValue)/mcp")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // deliberately no Authorization header
        request.httpBody = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.data(using: .utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 401)
    }

    func testWrongPath_Is404() async throws {
        let url = URL(string: "http://127.0.0.1:\(port.rawValue)/notes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data()
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }

    func testInvalidJSON_ReturnsParseError() async throws {
        let response = try await post("not valid json at all")
        let err = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(err["code"] as? Int, -32700)
    }

    // MARK: - Helpers

    private func post(_ body: String) async throws -> [String: Any] {
        let url = URL(string: "http://127.0.0.1:\(port.rawValue)/mcp")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let parsed = try JSONSerialization.jsonObject(with: data)
        return parsed as? [String: Any] ?? [:]
    }
}
