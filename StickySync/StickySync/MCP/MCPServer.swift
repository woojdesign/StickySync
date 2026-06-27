// MCPServer.swift
//
// Local-only HTTP server that exposes StickySync's notes via the Model
// Context Protocol. Listens on 127.0.0.1:47823, single POST /mcp endpoint
// speaking JSON-RPC 2.0. Bound to loopback so other devices on the
// network can't reach it; bearer-token auth so other local processes
// can't drive it without the user's explicit copy-paste.
//
// We hand-roll the HTTP/1.1 layer on top of NWListener / NWConnection
// because the protocol surface is tiny (one POST endpoint) and adding a
// real HTTP framework would be much more code than we save.

import Foundation
import Network
import NotesKit

@MainActor
final class MCPServer {
    static let defaultPort: NWEndpoint.Port = 47823

    /// The store to dispatch tool calls against. Held weakly so the
    /// server doesn't keep the app's NoteStore alive on quit.
    private weak var store: (AnyObject & NoteStore)?
    private let tools: MCPTools
    private let port: NWEndpoint.Port
    private(set) var authToken: String

    private var listener: NWListener?
    private(set) var isRunning = false

    /// Snapshot of the host:port + token the user pastes into Claude
    /// Code's config. Regenerated whenever the server (re)starts so a
    /// previously-shared token can't be reused after disable→enable.
    var configEndpoint: URL {
        URL(string: "http://127.0.0.1:\(port.rawValue)/mcp")!
    }

    init(store: AnyObject & NoteStore,
         port: NWEndpoint.Port = MCPServer.defaultPort,
         authToken: String = MCPServer.generateToken()) {
        self.store = store
        self.tools = MCPTools(store: store)
        self.port = port
        self.authToken = authToken
    }

    /// Begin listening. Throws on bind failure (typically port conflict —
    /// the UI surfaces this and lets the user pick a different port).
    func start() throws {
        guard !isRunning else { return }
        let params = NWParameters.tcp
        // Bind to the loopback interface only — anyone *on* this machine
        // who knows the port + token can drive the server, but nothing
        // on the LAN/WAN can reach it. `requiredInterfaceType` is the
        // right knob for listeners; `requiredLocalEndpoint` is for
        // outbound connections and returns EINVAL on a listener.
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { state in
            #if DEBUG
            if case .failed(let err) = state {
                NSLog("MCP listener failed: \(err)")
            }
            #endif
        }
        listener.start(queue: .main)
        isRunning = true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    /// Rotate the token (called when the user disables → re-enables AI
    /// access, so the previously-pasted config no longer works).
    func rotateToken() {
        authToken = Self.generateToken()
    }

    nonisolated static func generateToken() -> String {
        // 32 chars of url-safe alphabet — plenty for a localhost-only
        // capability token, short enough to copy-paste cleanly.
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
        return String((0..<32).map { _ in alphabet.randomElement()! })
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
            if case .cancelled = state { connection.cancel() }
        }
        connection.start(queue: .main)
        readRequest(connection, buffer: Data())
    }

    /// Read the HTTP request in chunks, parse once we have the full body
    /// (Content-Length header), dispatch, write the response, close.
    /// HTTP/1.0 close-after-response semantics — no keep-alive.
    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in
                if error != nil { connection.cancel(); return }
                var buf = buffer
                if let data { buf.append(data) }

                if let parsed = HTTPRequest.tryParse(from: buf) {
                    self.handle(parsed: parsed, on: connection)
                    return
                }

                if isComplete {
                    self.respond(.badRequest("incomplete request"), on: connection)
                    return
                }
                self.readRequest(connection, buffer: buf)
            }
        }
    }

    private func handle(parsed: HTTPRequest, on connection: NWConnection) {
        guard parsed.method == "POST", parsed.path == "/mcp" else {
            respond(.notFound("expected POST /mcp"), on: connection)
            return
        }
        guard let auth = parsed.headers["authorization"],
              auth == "Bearer \(authToken)" else {
            respond(.unauthorized(), on: connection)
            return
        }

        // JSON-RPC notification (no id) — no response body, just 202.
        // JSON-RPC request (has id) — full envelope back.
        guard let raw = parsed.body else {
            respond(.json("{}", status: 400), on: connection)
            return
        }
        let responseJSON = handleJSONRPC(body: raw)
        respond(.json(responseJSON, status: 200), on: connection)
    }

    // MARK: - JSON-RPC dispatch

    private func handleJSONRPC(body: Data) -> String {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        guard let request = try? decoder.decode(MCPRequest.self, from: body) else {
            let resp = MCPResponse(id: nil, error: .parseError)
            return encode(resp, encoder: encoder)
        }

        switch request.method {
        case "initialize":
            let result = MCPInitializeResult(
                protocolVersion: "2025-03-26",
                capabilities: .init(tools: .init(listChanged: false)),
                serverInfo: .init(name: "StickySync", version: appVersion())
            )
            return encode(MCPResponse(id: request.id, result: jsonify(result)), encoder: encoder)

        case "notifications/initialized", "notifications/cancelled":
            // Notifications don't return a body, but JSON-RPC over HTTP
            // expects a response — send a benign empty result.
            return "{}"

        case "ping":
            return encode(MCPResponse(id: request.id, result: .object([:])), encoder: encoder)

        case "tools/list":
            let result = MCPListToolsResult(tools: MCPTools.definitions)
            return encode(MCPResponse(id: request.id, result: jsonify(result)), encoder: encoder)

        case "tools/call":
            guard let params = request.params?.raw,
                  let name = params["name"] as? String else {
                return encode(MCPResponse(id: request.id, error: .invalidParams), encoder: encoder)
            }
            let args = (params["arguments"] as? [String: Any]) ?? [:]
            let result = tools.dispatch(toolName: name, arguments: args)
            return encode(MCPResponse(id: request.id, result: jsonify(result)), encoder: encoder)

        default:
            return encode(MCPResponse(id: request.id, error: .methodNotFound), encoder: encoder)
        }
    }

    private func encode<T: Encodable>(_ value: T, encoder: JSONEncoder) -> String {
        (try? encoder.encode(value))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"jsonrpc":"2.0","error":{"code":-32603,"message":"encode failed"}}"#
    }

    /// Re-encode a typed value into our `MCPJSONValue` shape so the
    /// JSON-RPC envelope's `result` field can carry any tool's output
    /// without bespoke encoding paths.
    private func jsonify<T: Encodable>(_ value: T) -> MCPJSONValue {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let decoded = try? JSONDecoder().decode(MCPJSONValue.self, from: data)
        else { return .object([:]) }
        return decoded
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Response shaping

    private func respond(_ resp: HTTPResponse, on connection: NWConnection) {
        let payload = resp.serialize()
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Minimal HTTP/1.1 request parser + response builder

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]   // lowercased keys
    let body: Data?

    static func tryParse(from buffer: Data) -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[..<headerEnd.lowerBound]
        let headerStr = String(decoding: headerData, as: UTF8.self)
        let lines = headerStr.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[String(key)] = value
        }

        let bodyStart = headerEnd.upperBound
        let body: Data?
        if let lengthStr = headers["content-length"], let length = Int(lengthStr) {
            let remaining = buffer.count - bodyStart
            if remaining < length { return nil }   // need more data
            body = buffer[bodyStart..<bodyStart + length]
        } else {
            body = nil
        }
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

private enum HTTPResponse {
    case json(String, status: Int)
    case badRequest(String)
    case notFound(String)
    case unauthorized

    static func unauthorized() -> HTTPResponse { .unauthorized }

    func serialize() -> Data {
        let (status, body, contentType): (Int, String, String)
        switch self {
        case .json(let s, let st):     (status, body, contentType) = (st, s, "application/json")
        case .badRequest(let msg):     (status, body, contentType) = (400, msg, "text/plain")
        case .notFound(let msg):       (status, body, contentType) = (404, msg, "text/plain")
        case .unauthorized:            (status, body, contentType) = (401, "unauthorized", "text/plain")
        }
        let phrase = statusPhrase(status)
        let head = """
        HTTP/1.1 \(status) \(phrase)\r
        Content-Type: \(contentType); charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r

        """
        return Data((head + body).utf8)
    }

    private func statusPhrase(_ s: Int) -> String {
        switch s {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default:  return "OK"
        }
    }
}
