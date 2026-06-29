// HotkeyStateMachineTests.swift
//
// Pins the tap-to-toggle state machine inside HotkeyController. The
// Carbon registration layer isn't exercised here (it's a system call
// and unit-testing it would be pointless); these tests target the
// pure state transitions by invoking handleRawKeyDown / handleRawKeyUp
// directly.
//
// Gesture model (0.8.5): every press toggles. KEY_UP is silent —
// no timing windows, no tap-vs-hold distinction. Sean's 0.8.4
// report: the prior tap-or-hold hybrid model required holding a
// two-key chord for any utterance longer than 300ms (uncomfortable)
// or precisely-timed taps (fiddly). Pure toggle removes both.

import XCTest
@testable import StickySync

final class HotkeyStateMachineTests: XCTestCase {

    /// First press starts; second press stops. The most basic contract.
    func testPress_TogglesRecording() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown()
        XCTAssertEqual(events, [.started])

        h.handleRawKeyDown()
        XCTAssertEqual(events, [.started, .stopped])
    }

    /// KEY_UP events are silent — by design. A long press (user
    /// holding the chord while talking) must NOT accidentally end
    /// the session on release.
    func testKeyUp_IsAlwaysSilent() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        // Press, hold for a while, release — recording stays on.
        h.handleRawKeyDown()
        Thread.sleep(forTimeInterval: 0.5)
        h.handleRawKeyUp()
        XCTAssertEqual(events, [.started],
                       "release must not fire stopped — toggle is on press only")

        // Press again — now it stops.
        h.handleRawKeyDown()
        XCTAssertEqual(events, [.started, .stopped])
    }

    /// Press → stop → press → start: state returns to idle cleanly so
    /// the next session works.
    func testPress_AfterStop_StartsAgain() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown(); h.handleRawKeyDown()  // start, stop
        h.handleRawKeyDown()                         // start again
        XCTAssertEqual(events, [.started, .stopped, .started])
    }

    /// Multiple key-ups between presses → all silent. Carbon shouldn't
    /// deliver these but defensive against repeat-key behavior.
    func testRepeatedKeyUp_StaysSilent() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown()
        h.handleRawKeyUp()
        h.handleRawKeyUp()
        h.handleRawKeyUp()
        XCTAssertEqual(events, [.started])
    }
}
