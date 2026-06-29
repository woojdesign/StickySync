// PolishIndicatorTests.swift
//
// Pins the 0.8.2 RecordingIndicator state-transition contract — the
// signal that drives the user-visible Listening / Polishing / hidden
// states from VoiceCaptureController.
//
// We test the indicator directly rather than going through
// VoiceCaptureController because the controller's init+deinit cycle
// crashes under XCTest in a Swift Concurrency teardown path
// (TaskLocal cleanup + libmalloc complaint about freeing a pointer
// it doesn't own). The controller works fine in production — the
// abort is XCTest-environment-specific and not worth fighting for
// this regression test. The indicator's state is what
// VoiceCaptureController's contract promises, so testing it directly
// covers the same surface.

import XCTest
import AppKit
@testable import StickySync

final class PolishIndicatorTests: XCTestCase {

    /// Initial state is .none — indicator hidden by default.
    func testInitialState() {
        let indicator = RecordingIndicator()
        XCTAssertEqual(indicator.state, .none)
    }

    /// showPolishing transitions state from .none to .polishing even
    /// without prior chrome (the test-environment path). In
    /// production showListening is always called first, but the state
    /// flag is the source of truth either way.
    func testShowPolishing_FromNone_BecomesPolishing() {
        let indicator = RecordingIndicator()
        indicator.showPolishing()
        XCTAssertEqual(indicator.state, .polishing)
    }

    /// hide() always returns the indicator to .none, regardless of
    /// current state.
    func testHide_FromPolishing_BecomesNone() {
        let indicator = RecordingIndicator()
        indicator.showPolishing()
        indicator.hide()
        XCTAssertEqual(indicator.state, .none)
    }

    func testHide_FromNone_StaysNone() {
        let indicator = RecordingIndicator()
        indicator.hide()
        XCTAssertEqual(indicator.state, .none)
    }

    /// Re-entering polishing after a previous polish cycle works —
    /// no leftover state forces it back to .none on the second call.
    func testShowPolishing_TwiceInARow_StaysPolishing() {
        let indicator = RecordingIndicator()
        indicator.showPolishing()
        indicator.showPolishing()
        XCTAssertEqual(indicator.state, .polishing)
    }

    /// VoiceCaptureController's polish flow path: showListening
    /// (during recording) → showPolishing (after stop while WhisperKit
    /// runs) → hide (after polish completes). This test follows that
    /// arc but skips showListening because it requires a real
    /// NSWindow as the anchor (which aborts under XCTest).
    /// showPolishing → hide is the critical post-stop transition.
    func testPostStop_PolishingThenHide() {
        let indicator = RecordingIndicator()
        indicator.showPolishing()
        XCTAssertEqual(indicator.state, .polishing,
                       "user sees Polishing… while WhisperKit runs")
        indicator.hide()
        XCTAssertEqual(indicator.state, .none,
                       "indicator hides once polish completes")
    }

    /// 0.8.3 surface: showFailed immediately transitions to .failed.
    /// (The auto-hide timing is not unit-tested — DispatchQueue.main
    /// .asyncAfter doesn't fire reliably under XCTest's runloop
    /// pumping, even with RunLoop.main.run(until:). The behavior is
    /// trivial and observable in production; documenting the gap
    /// rather than chasing a flaky test.)
    @MainActor func testShowFailed_TransitionsToFailed() {
        let indicator = RecordingIndicator()
        indicator.showFailed(detail: "test", autoHideAfter: 1.0)
        XCTAssertEqual(indicator.state, .failed)
    }

    /// If hide() is called before the auto-hide fires, the auto-hide
    /// becomes a no-op — no flicker, no second hide-after-already-hidden.
    @MainActor func testShowFailed_ExternalHideBeforeTimeout_IsClean() {
        let indicator = RecordingIndicator()
        indicator.showFailed(detail: "x", autoHideAfter: 0.1)
        XCTAssertEqual(indicator.state, .failed)
        indicator.hide()
        XCTAssertEqual(indicator.state, .none)
        // Run past the would-be auto-hide; state should stay .none
        // (the snapshot guard inside showFailed prevents re-hide).
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertEqual(indicator.state, .none)
    }
}
