// HotkeyController.swift
//
// Coordinator over the underlying HotkeySource. Owns the tap-to-toggle
// state machine and the public Event surface that VoiceCaptureController
// consumes; delegates raw hotkey detection to whichever source the user
// picked (Carbon chord like ⌥V, or NSEvent-based Fn).
//
// Gesture: **pure tap-to-toggle.** Every press toggles recording —
// press starts, press stops. KEY_UP events are silent. No timing
// windows, no tap-vs-hold distinction, no finger strain from
// holding a chord while talking.

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

    /// Pure tap-to-toggle: every press toggles recording. KEY_UP is
    /// silent.
    private enum State { case idle, recording }
    private var state: State = .idle

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
        state = .idle
    }

    /// Called from the source on KEY_DOWN.
    func handleRawKeyDown() {
        switch state {
        case .idle:
            state = .recording
            onEvent?(.started)
        case .recording:
            state = .idle
            onEvent?(.stopped)
        }
    }

    /// Called from the source on KEY_UP. No-op by design — the toggle
    /// fires on press, releases are silent so a long press doesn't
    /// accidentally end the session.
    func handleRawKeyUp() {}

    deinit { unregister() }
}
