// HotkeyController.swift
//
// Coordinator over the underlying HotkeySource. Owns the per-mode
// gesture state machine and the public Event surface that
// VoiceCaptureController consumes; delegates raw hotkey detection
// to whichever source the user picked.
//
// **Gesture per mode** (0.8.7):
//   - `.chord` (⌥V): tap-to-toggle. Every press toggles recording;
//     releases are silent. Holding the chord is uncomfortable, so we
//     don't depend on hold semantics.
//   - `.fn` (Fn alone): hold-to-talk. Press Fn → start, release Fn
//     → stop. Single key is comfortable to hold; press-release maps
//     naturally to recording lifecycle.

import AppKit
import Carbon.HIToolbox

final class HotkeyController {

    enum Event { case started, stopped }
    enum Mode: String { case chord, fn }

    /// Called on the main thread for each hotkey transition. Set by
    /// `VoiceCaptureController` to forward into the capture pipeline.
    var onEvent: ((Event) -> Void)?

    /// Active hotkey mode. Swap at runtime via `setMode(_:)`.
    private(set) var mode: Mode = .chord

    /// Test-only: set the gesture mode without standing up a source
    /// (Carbon registration / NSEvent monitor). Used by tests that
    /// exercise the per-mode state machine via direct
    /// handleRawKeyDown / handleRawKeyUp calls.
    func setModeForTesting(_ newMode: Mode) {
        mode = newMode
        toggleState = .idle
    }

    /// Gesture state for tap-to-toggle mode (chord). Hold-to-talk
    /// mode (fn) is stateless — keyDown → started, keyUp → stopped.
    private enum ToggleState { case idle, recording }
    private var toggleState: ToggleState = .idle

    private var source: HotkeySource?

    func setMode(_ newMode: Mode) {
        guard newMode != mode || source == nil else { return }
        source?.stop()
        source = nil
        mode = newMode
        let made: HotkeySource = {
            switch newMode {
            case .chord:
                // ⌥V — the prior default, retains tap-to-toggle on
                // a two-key chord. Configurable later if a third
                // chord option becomes useful.
                return CarbonChordSource(modifiers: UInt32(optionKey),
                                         keyCode: UInt32(kVK_ANSI_V))
            case .fn:
                return FnHotkeySource()
            }
        }()
        made.onKeyDown = { [weak self] in self?.handleRawKeyDown() }
        made.onKeyUp = { [weak self] in self?.handleRawKeyUp() }
        source = made
        made.start()
    }

    func register() {
        // Default to .chord if no mode has been set yet.
        if source == nil { setMode(mode) }
    }

    func unregister() {
        source?.stop()
        source = nil
        toggleState = .idle
    }

    /// Called from the source on KEY_DOWN.
    func handleRawKeyDown() {
        switch mode {
        case .chord:
            // Tap-to-toggle.
            switch toggleState {
            case .idle:
                toggleState = .recording
                onEvent?(.started)
            case .recording:
                toggleState = .idle
                onEvent?(.stopped)
            }
        case .fn:
            // Hold-to-talk: down → started.
            onEvent?(.started)
        }
    }

    /// Called from the source on KEY_UP.
    func handleRawKeyUp() {
        switch mode {
        case .chord:
            // No-op — toggle fires on press; releases are silent so a
            // long press doesn't accidentally end the session.
            break
        case .fn:
            // Hold-to-talk: up → stopped.
            onEvent?(.stopped)
        }
    }

    deinit { unregister() }
}
