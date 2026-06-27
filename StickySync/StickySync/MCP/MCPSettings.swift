// MCPSettings.swift
//
// Lightweight settings store for AI access. Persists the "enabled" flag
// and the generated bearer token in UserDefaults so the configuration
// survives app restarts — the user pastes the config snippet once, not
// every relaunch.
//
// Token is stored visibly (per the v1 design decision) rather than in
// Keychain. It's a localhost-only capability token; the threat model is
// "another local process driving the user's notes," and a UserDefaults
// read for that requires the same access the AI client already needs.

import Foundation
import Combine
import Network

@MainActor
final class MCPSettings: ObservableObject {
    static let shared = MCPSettings()

    private let enabledKey = "design.wooj.StickySync.MCP.enabled"
    private let tokenKey   = "design.wooj.StickySync.MCP.token"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var token: String

    private init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: enabledKey)
        if let existing = defaults.string(forKey: tokenKey), !existing.isEmpty {
            self.token = existing
        } else {
            let fresh = MCPServer.generateToken()
            defaults.set(fresh, forKey: tokenKey)
            self.token = fresh
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    /// Generate a fresh token. Called when the user explicitly rotates
    /// (e.g., after sharing a config snippet they shouldn't have).
    @discardableResult
    func rotateToken() -> String {
        let fresh = MCPServer.generateToken()
        token = fresh
        UserDefaults.standard.set(fresh, forKey: tokenKey)
        return fresh
    }

    /// The full config snippet to paste into `~/.claude/mcp.json` (or the
    /// equivalent for whichever MCP client the user runs). Includes both
    /// the URL and the bearer token in the header form Claude Code reads.
    var configJSON: String {
        let url = "http://127.0.0.1:\(MCPServer.defaultPort.rawValue)/mcp"
        return """
        {
          "mcpServers": {
            "stickysync": {
              "type": "http",
              "url": "\(url)",
              "headers": {
                "Authorization": "Bearer \(token)"
              }
            }
          }
        }
        """
    }
}
