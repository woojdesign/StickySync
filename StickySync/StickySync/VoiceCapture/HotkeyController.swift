// HotkeyController.swift
//
// Global hotkey registration for the Mac voice-to-sticky feature.
// Uses Carbon's `RegisterEventHotKey` — works app-wide without the
// accessibility permission (which is only needed if we wanted to
// *inject* keystrokes; we don't, we just listen).
//
// Gesture: **pure tap-to-toggle.** Every press toggles recording —
// press starts, press stops. KEY_UP events are silent. No timing
// windows, no tap-vs-hold distinction, no finger strain from
// holding a chord while talking. Sean's 0.8.4 report: holding the
// two-key chord was uncomfortable; the old hybrid model (short-tap-
// latches, long-press-holds) made every interaction a "did I tap
// or hold" guess. The simpler model wins.

import AppKit
import Carbon.HIToolbox

final class HotkeyController {

    enum Event { case started, stopped }

    /// Called on the main thread for each hotkey transition. Set by
    /// `VoiceCaptureController` to forward into the capture pipeline.
    var onEvent: ((Event) -> Void)?

    /// Returns true if the hotkey is currently registered.
    private(set) var isRegistered = false

    /// Default chord: **⌥V** (option + V). Two keys, mnemonic for
    /// "voice," reachable with one hand. Cut from the original
    /// ⌃⌥V — Sean called the three-key chord "awkward as hell to
    /// toggle." Conflict: ⌥V types ✓ when no app captures it; the
    /// hotkey registration intercepts before insertion so this is a
    /// non-issue while StickySync is running. Configurable later.
    private static let defaultModifiers: UInt32 = UInt32(optionKey)
    private static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_V)

    /// Four-char-code signature so the OS can route hotkey events
    /// back to our handler. "Stky" is arbitrary; just needs to be
    /// unique within our process.
    private static let signature: OSType = {
        let chars = "Stky".utf8
        var result: UInt32 = 0
        for byte in chars { result = (result << 8) | UInt32(byte) }
        return result
    }()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Pure tap-to-toggle: every press toggles recording. KEY_UP is
    /// silent.
    private enum State { case idle, recording }
    private var state: State = .idle

    /// Called from the Carbon event handler on KEY_DOWN.
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

    /// Called from the Carbon event handler on KEY_UP. No-op by
    /// design — the toggle fires on press, releases are silent so a
    /// long press doesn't accidentally end the session.
    func handleRawKeyUp() {}

    func register() {
        guard !isRegistered else { return }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            Self.defaultKeyCode,
            Self.defaultModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef)
        guard status == noErr else {
            NSLog("HotkeyController: RegisterEventHotKey failed status=\(status)")
            return
        }
        installEventHandler()
        isRegistered = true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        isRegistered = false
    }

    private func installEventHandler() {
        var eventTypes: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }
                let controller = Unmanaged<HotkeyController>
                    .fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(eventRef)
                DispatchQueue.main.async {
                    switch Int(kind) {
                    case kEventHotKeyPressed:  controller.handleRawKeyDown()
                    case kEventHotKeyReleased: controller.handleRawKeyUp()
                    default: break
                    }
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &eventHandlerRef)
    }

    deinit { unregister() }
}
