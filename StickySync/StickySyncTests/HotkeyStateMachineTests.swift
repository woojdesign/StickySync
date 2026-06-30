// HotkeyStateMachineTests.swift
//
// Pins the per-mode gesture state machine inside HotkeyController.
// The Carbon registration and NSEvent monitor layers aren't
// exercised here; these tests target the pure state transitions by
// invoking handleRawKeyDown / handleRawKeyUp directly.
//
// Gesture per mode (0.8.7):
//   - `.chord` (⌥V): tap-to-toggle. Press toggles, release silent.
//   - `.fn` (Fn alone): hold-to-talk. Press = started, release =
//     stopped.

import XCTest
@testable import StickySync

final class HotkeyStateMachineTests: XCTestCase {

    // MARK: - Chord mode (tap-to-toggle)

    func testChord_Press_TogglesRecording() {
        let h = HotkeyController()
        h.setModeForTesting(.chord)
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown()
        XCTAssertEqual(events, [.started])
        h.handleRawKeyDown()
        XCTAssertEqual(events, [.started, .stopped])
    }

    func testChord_KeyUp_IsAlwaysSilent() {
        let h = HotkeyController()
        h.setModeForTesting(.chord)
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown()
        Thread.sleep(forTimeInterval: 0.5)
        h.handleRawKeyUp()
        XCTAssertEqual(events, [.started],
                       "release in chord mode must not fire stopped — toggle is on press only")
        h.handleRawKeyDown()
        XCTAssertEqual(events, [.started, .stopped])
    }

    func testChord_AfterStop_StartsAgain() {
        let h = HotkeyController()
        h.setModeForTesting(.chord)
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown(); h.handleRawKeyDown()  // start, stop
        h.handleRawKeyDown()                         // start
        XCTAssertEqual(events, [.started, .stopped, .started])
    }

    // MARK: - Fn mode (hold-to-talk)

    /// Press → started, release → stopped. The recording lifecycle
    /// maps directly to key state.
    func testFn_PressAndRelease_StartsThenStops() {
        let h = HotkeyController()
        h.setModeForTesting(.fn)
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown()
        XCTAssertEqual(events, [.started])
        h.handleRawKeyUp()
        XCTAssertEqual(events, [.started, .stopped])
    }

    /// Multiple press-release cycles → multiple started/stopped pairs.
    func testFn_TwoCycles() {
        let h = HotkeyController()
        h.setModeForTesting(.fn)
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        h.handleRawKeyDown(); h.handleRawKeyUp()
        h.handleRawKeyDown(); h.handleRawKeyUp()
        XCTAssertEqual(events, [.started, .stopped, .started, .stopped])
    }

    /// Switching modes between captures: chord-toggle cycle then a
    /// fn-hold cycle, each runs cleanly without state leak from the
    /// other.
    func testModeSwitch_BetweenSessions_Clean() {
        let h = HotkeyController()
        var events: [HotkeyController.Event] = []
        h.onEvent = { events.append($0) }

        // Chord toggle cycle.
        h.setModeForTesting(.chord)
        h.handleRawKeyDown(); h.handleRawKeyDown()
        XCTAssertEqual(events, [.started, .stopped])

        // Switch to Fn, hold cycle.
        h.setModeForTesting(.fn)
        h.handleRawKeyDown(); h.handleRawKeyUp()
        XCTAssertEqual(events, [.started, .stopped, .started, .stopped])
    }
}
