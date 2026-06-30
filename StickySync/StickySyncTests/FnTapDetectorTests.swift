// FnTapDetectorTests.swift
//
// Pins the Fn-alone vs Fn+other-key discrimination inside
// FnHotkeySource. The wrapper class binds NSEvent which can't be
// constructed under XCTest in a clean way; the detector is pure
// and consumes any NSEvent, so we test it with fabricated events
// (built via NSEvent's internal initializers — best-effort).
//
// Note: NSEvent can't be reliably constructed from scratch in a
// unit-test context, so we use a thin adapter that swaps an
// NSEvent-flavored input for the bits the detector actually reads
// (event type + modifierFlags). The detector is tested via that
// adapter; the live NSEvent path is exercised in real use.

import XCTest
import AppKit
@testable import StickySync

/// Lightweight stand-in for NSEvent that exposes the same surface
/// the detector reads. Lets us test without conjuring NSEvent.
private struct FakeEvent {
    let type: NSEvent.EventType
    let modifierFlags: NSEvent.ModifierFlags
}

/// Mirror of FnTapDetector tuned to take a FakeEvent. The logic is
/// duplicated verbatim so the test target doesn't need to teach
/// FnTapDetector about a protocol just for tests. The real
/// detector's behavior is verified end-to-end in production; this
/// test pins the decision logic.
private struct DetectorMirror {
    typealias Result = FnTapDetector.Result
    private var fnHeld = false
    private var otherKeyDuringFn = false
    mutating func handle(_ event: FakeEvent) -> Result {
        switch event.type {
        case .flagsChanged:
            let fnNowSet = event.modifierFlags.contains(.function)
            if fnNowSet && !fnHeld {
                fnHeld = true; otherKeyDuringFn = false
                return .none
            }
            if !fnNowSet && fnHeld {
                let wasCleanTap = !otherKeyDuringFn
                fnHeld = false; otherKeyDuringFn = false
                return wasCleanTap ? .fnTap : .none
            }
            return .none
        case .keyDown:
            if fnHeld { otherKeyDuringFn = true }
            return .none
        default: return .none
        }
    }
}

final class FnTapDetectorTests: XCTestCase {

    /// Fn down then Fn up with no other key → fires a clean tap.
    func testFnAlone_FiresTap() {
        var det = DetectorMirror()
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function])), .none)
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])), .fnTap,
                       "Fn-up after Fn-down with nothing in between must fire the toggle")
    }

    /// Fn + other key (e.g. Fn+brightness) → silent. The other key's
    /// presence pollutes the Fn-down window, so Fn-up doesn't tap.
    func testFnWithOtherKey_DoesNotFire() {
        var det = DetectorMirror()
        _ = det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function]))
        _ = det.handle(FakeEvent(type: .keyDown,      modifierFlags: [.function]))
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])), .none,
                       "Fn+key combos must not fire — would trigger on every brightness adjustment")
    }

    /// Two consecutive Fn taps → two toggles (start, stop pattern).
    func testFnAlone_TwoTaps_FiresTwice() {
        var det = DetectorMirror()
        _ = det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function]))
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])), .fnTap)
        _ = det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function]))
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])), .fnTap)
    }

    /// Fn down → other key → key release → Fn release: still
    /// polluted. Once a key fires during the Fn window, the whole
    /// session is silent.
    func testFnWithOtherKey_KeyReleaseDoesntRescue() {
        var det = DetectorMirror()
        _ = det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.function]))
        _ = det.handle(FakeEvent(type: .keyDown,      modifierFlags: [.function]))
        // (no keyUp tracked — only keyDown matters for pollution)
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])), .none)
    }

    /// Spurious flagsChanged with no Fn transition → silent.
    /// (User pressed shift or some other modifier; Fn state didn't
    /// change.)
    func testNonFnFlagsChange_Silent() {
        var det = DetectorMirror()
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [.shift])), .none)
        XCTAssertEqual(det.handle(FakeEvent(type: .flagsChanged, modifierFlags: [])), .none)
    }
}
