// MCPProtocol.swift
//
// Model Context Protocol shapes — JSON-RPC 2.0 envelopes plus the
// MCP-specific method types we implement. We hand-roll the protocol
// instead of pulling in the official Swift SDK because the surface we
// need is small (six tools, one transport, no resources, no
// notifications) and the dependency churn isn't worth it.
//
// Spec: https://modelcontextprotocol.io/specification/

import Foundation

// MARK: - JSON-RPC 2.0 envelope

/// Either an integer or a string id — JSON-RPC allows both. Notifications
/// (no response expected) omit the id entirely.
enum MCPID: Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.typeMismatch(
            MCPID.self,
            .init(codingPath: decoder.codingPath, debugDescription: "id must be int or string"))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

struct MCPRequest: Decodable {
    let jsonrpc: String
    let id: MCPID?
    let method: String
    let params: MCPParamsBag?
}

/// JSON-RPC params are a free-form object — we decode them into a
/// type-erased bag and unwrap per-method when dispatching.
struct MCPParamsBag: Decodable {
    let raw: [String: Any]

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let data = try c.decode(MCPJSONValue.self)
        guard case .object(let dict) = data else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                .init(codingPath: decoder.codingPath, debugDescription: "params must be object"))
        }
        self.raw = dict.mapValues { $0.unwrapped }
    }
}

struct MCPResponse: Encodable {
    let jsonrpc: String
    let id: MCPID?
    let result: MCPJSONValue?
    let error: MCPError?

    init(id: MCPID?, result: MCPJSONValue) {
        self.jsonrpc = "2.0"; self.id = id; self.result = result; self.error = nil
    }
    init(id: MCPID?, error: MCPError) {
        self.jsonrpc = "2.0"; self.id = id; self.result = nil; self.error = error
    }
}

struct MCPError: Encodable {
    let code: Int
    let message: String
    let data: MCPJSONValue?

    init(code: Int, message: String, data: MCPJSONValue? = nil) {
        self.code = code; self.message = message; self.data = data
    }

    // Standard JSON-RPC error codes (and a few MCP-specific ones).
    static let parseError = MCPError(code: -32700, message: "Parse error")
    static let invalidRequest = MCPError(code: -32600, message: "Invalid Request")
    static let methodNotFound = MCPError(code: -32601, message: "Method not found")
    static let invalidParams = MCPError(code: -32602, message: "Invalid params")
    static let internalError = MCPError(code: -32603, message: "Internal error")
    static func unauthorized(_ msg: String = "Missing or invalid Authorization header") -> MCPError {
        MCPError(code: -32001, message: msg)
    }
}

// MARK: - MCP method shapes

/// Returned from `initialize`. We advertise tools support; nothing else.
struct MCPInitializeResult: Encodable {
    let protocolVersion: String
    let capabilities: Capabilities
    let serverInfo: ServerInfo

    struct Capabilities: Encodable {
        let tools: ToolsCapability
    }
    struct ToolsCapability: Encodable {
        let listChanged: Bool
    }
    struct ServerInfo: Encodable {
        let name: String
        let version: String
    }
}

struct MCPToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: MCPJSONValue
}

struct MCPListToolsResult: Encodable {
    let tools: [MCPToolDefinition]
}

struct MCPCallToolResult: Encodable {
    let content: [MCPContent]
    let isError: Bool

    struct MCPContent: Encodable {
        let type: String
        let text: String
    }

    static func text(_ s: String) -> MCPCallToolResult {
        .init(content: [.init(type: "text", text: s)], isError: false)
    }
    static func error(_ s: String) -> MCPCallToolResult {
        .init(content: [.init(type: "text", text: s)], isError: true)
    }
}

// MARK: - Generic JSON value (so the result field can carry any shape)

indirect enum MCPJSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([MCPJSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: MCPJSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported JSON value")
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// Convert to plain `Any` for ergonomic param access in tool dispatch.
    var unwrapped: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.unwrapped }
        case .object(let v): return v.mapValues { $0.unwrapped }
        }
    }
}
