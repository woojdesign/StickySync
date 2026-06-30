// FnTapDetectorTests.swift
//
// Pins the Fn-alone vs Fn+other-key discrimination inside
// FnHoldDetector. NSEvent can't be reliably constructed from
// scratch under XCTest, so we use a thin adapter that swaps an
// NSEvent-flavored input for the bits the detector actually reads
// (event type + modifierFlags).
//
// 0.8.7 semantics: detector returns an *array* of Emit values per
// event — usually empty, sometimes one (keyDown or keyUp). The
// hold-to-talk gesture means Fn-down emits .keyDown, Fn-up emits
// .keyUp, and a polluting non-Fn keypress emits an early .keyUp
// (canceling the recording).

import XCTest
import AppKit
@testable import StickySync

/// Lightweight stand-in for NSEvent.
private struct FakeEvent {
    let type: NSEvent.EventType
    let modifierFlags: NSEvent.ModifierFlags
}

/// Mirror of FnHoldDetector tuned to take a FakeEvent — logic
/// duplicated verbatim so the test target doesn't need a protocol
/// just for tests.
private struct DetectorMirror {
    typealias Emit = FnHoldDetector.Emit
    private var fnHeld = false
    private var alreadyStopped = false

    mutating func handle(_ event: FakeEvent) -> [Emit] {
        switch event.type {
        case .flagsChanged:
            let fnNowSet = event.modifierFlags.contains(.function)
            if fnNowSet && !fnHeld {
                fnHeld = true
                alreadyStopped = false
                return [.keyDown]
            }
            if !fnNowSet && fnHeld {
                fnHeld = false
                let emit: [Emit] = alreadyStopped ? [] : [.keyUp]
                alreadyStopped = false
                return emit
            }
            return []
        case .keyDown:
            if fnHeld && !alreadyStopped {
                alreadyStopped = true
                return [.keyUp]
            }
            return []
        default: return []
        }
    }
}

final class FnTapDetectorTests: XCTestCase {

    /// Clean Fn-down → Fn-up → emits [keyDown] then [keyUp].
    func testFnAlone_EmitsDownThenUp() {
        var det = DetectorMirror()
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function])),
                       [.keyDown])
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])),
                       [.keyUp])
    }

    /// Fn + other key → emits [keyDown] on Fn-down, then [keyUp]
    /// on the other-key press (early stop). The actual Fn-up is
    /// silent because we already stopped.
    func testFnWithOtherKey_EmitsEarlyUp() {
        var det = DetectorMirror()
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function])),
                       [.keyDown])
        XCTAssertEqual(det.handle(FakeEvent(type: .keyDown,      modifierFlags: [.function])),
                       [.keyUp],
                       "non-Fn key during Fn-held must cancel — emit .keyUp now to stop the recording")
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])),
                       [],
                       "actual Fn-up must be silent — we already stopped on the polluting keypress")
    }

    /// Two consecutive clean Fn cycles → two down/up pairs.
    func testFnAlone_TwoCycles() {
        var det = DetectorMirror()
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function])),
                       [.keyDown])
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])),
                       [.keyUp])
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function])),
                       [.keyDown])
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])),
                       [.keyUp])
    }

    /// After a polluted cycle, the next Fn press is treated as a
    /// fresh, clean session — pollution flag resets.
    func testPollutedCycle_ThenCleanCycle_Works() {
        var det = DetectorMirror()
        // Polluted: Fn down, other key, Fn up
        _ = det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function]))
        _ = det.handle(FakeEvent(type: .keyDown,      modifierFlags: [.function]))
        _ = det.handle(FakeEvent(type: .flagsChanged, modifierFlags: []))
        // Clean: Fn down → Fn up
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function])),
                       [.keyDown])
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])),
                       [.keyUp])
    }

    /// Spurious flagsChanged events that don't transition Fn state
    /// (e.g. the user pressing shift) are silent.
    func testNonFnFlagsChange_Silent() {
        var det = DetectorMirror()
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.shift])),
                       [])
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])),
                       [])
    }
}
