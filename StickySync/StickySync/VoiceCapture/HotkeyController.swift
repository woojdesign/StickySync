// HotkeyController.swift
//
// Global hotkey registration for the Mac voice-to-sticky feature.
// Uses Carbon's `RegisterEventHotKey` — works app-wide without the
// accessibility permission (which is only needed if we wanted to
// *inject* keystrokes; we don't, we just listen).
//
// Gesture: **tap or hold**. A short press (< 300ms before release)
// latches recording on — release doesn't stop it. A long press
// (>= 300ms) is hold-to-talk — release stops. Tapping again while
// latched stops. Both gestures coexist; the user picks per
// utterance whichever fits.

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

    /// State machine for tap-or-hold gesture.
    private enum State {
        case idle
        case recording(downAt: Date)
        case latched
        case stoppingLatched
    }
    private var state: State = .idle
    /// Press shorter than this is a "tap" (latch); longer is a "hold"
    /// (release stops). Carbon delivers KEY_DOWN and KEY_UP with their
    /// system timestamps; we compute the duration off our own Dates
    /// since we don't need millisecond accuracy.
    private static let tapThreshold: TimeInterval = 0.3

    /// Called from the Carbon event handler on KEY_DOWN.
    func handleRawKeyDown() {
        switch state {
        case .idle:
            state = .recording(downAt: Date())
            onEvent?(.started)
        case .latched:
            // Tap-to-stop while latched. The recording is ending here;
            // the matching KEY_UP just returns us to idle without
            // starting a new session.
            state = .stoppingLatched
            onEvent?(.stopped)
        case .recording, .stoppingLatched:
            break  // Carbon shouldn't deliver back-to-back DOWNs
        }
    }

    /// Called from the Carbon event handler on KEY_UP.
    func handleRawKeyUp() {
        switch state {
        case .recording(let downAt):
            if Date().timeIntervalSince(downAt) < Self.tapThreshold {
                // Tap → latch on; recording continues. No event to the
                // outer pipeline; the session is already running.
                state = .latched
            } else {
                // Hold-release → stop.
                state = .idle
                onEvent?(.stopped)
            }
        case .stoppingLatched:
            state = .idle
        case .idle, .latched:
            break
        }
    }

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
