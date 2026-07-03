// MCPPortTests.swift
//
// 0.11.2: pins that Debug and Release use DIFFERENT MCP ports so a
// running Debug build doesn't collide with Sean's Release build.
// Test runs under DEBUG (that's the only config that runs the test
// target), so we assert the Debug port here. The `#else` branch is
// covered by Release build compilation only.

import XCTest
import Network
@testable import StickySync

@MainActor
final class MCPPortTests: XCTestCase {

    /// The Debug port constant should be 47824. We check against the
    /// concrete value directly instead of gating via `#if DEBUG` in
    /// the test — the test target may not carry the DEBUG flag even
    /// when the main app target does, and the value we're pinning is
    /// the *product* of the main app's `#if`.
    func testDefaultPort_IsDebugPort() {
        XCTAssertEqual(MCPServer.defaultPort.rawValue, 47824,
            "Test target links the Debug build of StickySync → MCPServer.defaultPort must be 47824.")
    }
}
