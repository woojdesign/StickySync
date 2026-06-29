// HotkeyController.swift
//
// Global hotkey registration for the Mac voice-to-sticky feature.
// Uses Carbon's `RegisterEventHotKey` — works app-wide without the
// accessibility permission (which is only needed if we wanted to
// *inject* keystrokes; we don't, we just listen).
//
// V1 behavior: hold-to-record. KEY_DOWN fires `started`,
// KEY_UP fires `stopped`. Double-tap-to-latch is a planned V2
// follow-up (a more nuanced state machine; getting the hold flow
// shipping first to validate the audio + Whisper layers).

import AppKit
import Carbon.HIToolbox

final class HotkeyController {

    enum Event { case started, stopped }

    /// Called on the main thread for each hotkey transition. Set by
    /// `VoiceCaptureController` to forward into the capture pipeline.
    var onEvent: ((Event) -> Void)?

    /// Returns true if the hotkey is currently registered.
    private(set) var isRegistered = false

    /// Default chord: ⌃⌥V. Three modifiers + V — unlikely to collide
    /// with any system or app shortcut. Configurable later.
    private static let defaultModifiers: UInt32 = UInt32(controlKey | optionKey)
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
                let event: Event
                switch Int(kind) {
                case kEventHotKeyPressed:  event = .started
                case kEventHotKeyReleased: event = .stopped
                default:                   return noErr
                }
                DispatchQueue.main.async { controller.onEvent?(event) }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &eventHandlerRef)
    }

    deinit { unregister() }
}
