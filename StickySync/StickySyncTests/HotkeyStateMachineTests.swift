// HotkeyStateMachineTests.swift
//
// Pins the tap/hold/latch state machine inside HotkeyController. The
// Carbon registration layer isn't exercised here (it's a system call
// and unit-testing it would be pointless); these tests target the
// pure state transitions by invoking handleRawKeyDown / handleRawKeyUp
// directly.

import XCTest
@testable import StickySync

final class HotkeyStateMachineTests: XCTestCase {

    /// Hold the hotkey for longer than tapThreshold then release → one
    /// started + one stopped, no extras.
    func testHold_FiresStartedThenStoppedOnRelease() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown()
        Thread.sleep(forTimeInterval: 0.35)   // exceed 300ms tap threshold
        h.handleRawKeyUp()

        XCTAssertEqual(events, [.started, .stopped])
    }

    /// Quick tap → latches recording on. Release does NOT fire stopped.
    /// Second tap (next press) stops.
    func testTap_LatchesOn_NextPressStops() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        // Tap 1 (latch on): press + release < 300ms
        h.handleRawKeyDown()
        h.handleRawKeyUp()
        XCTAssertEqual(events, [.started], "release after a tap must NOT fire stopped — the latch holds the recording on")

        // Tap 2 (stop): the next press fires stopped immediately
        h.handleRawKeyDown()
        XCTAssertEqual(events, [.started, .stopped])

        // The matching key-up after the stop tap is silent — no new
        // session started, the recording is fully ended.
        h.handleRawKeyUp()
        XCTAssertEqual(events, [.started, .stopped])
    }

    /// Tap → latch → hold → release → latch should be CLEARED by the
    /// stopping tap, not re-entered by the long press.
    func testTap_Latch_ThenHoldRelease_IsCleanIdle() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        // Tap: latch on
        h.handleRawKeyDown(); h.handleRawKeyUp()
        // Tap again: stop
        h.handleRawKeyDown(); h.handleRawKeyUp()
        // Now hold-release: should be a normal session, not a no-op
        h.handleRawKeyDown()
        Thread.sleep(forTimeInterval: 0.35)
        h.handleRawKeyUp()

        XCTAssertEqual(events, [.started, .stopped, .started, .stopped])
    }

    /// Two consecutive holds without a tap in between → two clean
    /// started/stopped pairs.
    func testHold_ThenHold_DoubleSession() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown()
        Thread.sleep(forTimeInterval: 0.35)
        h.handleRawKeyUp()

        h.handleRawKeyDown()
        Thread.sleep(forTimeInterval: 0.35)
        h.handleRawKeyUp()

        XCTAssertEqual(events, [.started, .stopped, .started, .stopped])
    }
}
