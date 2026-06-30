// CarbonChordSource.swift
//
// Carbon-based global hotkey source for a modifier+key chord (e.g.
// ⌥V). Works app-wide without accessibility permission — Carbon's
// RegisterEventHotKey is the sanctioned path for "listen for a
// chord," vs. NSEvent global monitors which need accessibility.
//
// Caveat: Carbon's modifier mask doesn't include Fn. For Fn-based
// hotkeys, see `FnHotkeySource`.

import AppKit
import Carbon.HIToolbox

final class CarbonChordSource: HotkeySource {

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    let modifiers: UInt32
    let keyCode: UInt32

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isRegistered = false

    /// Four-char-code signature so the OS can route hotkey events
    /// back to our handler. "Stky" is arbitrary; just needs to be
    /// unique within our process.
    private static let signature: OSType = {
        let chars = "Stky".utf8
        var result: UInt32 = 0
        for byte in chars { result = (result << 8) | UInt32(byte) }
        return result
    }()

    init(modifiers: UInt32, keyCode: UInt32) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    func start() {
        guard !isRegistered else { return }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            NSLog("CarbonChordSource: RegisterEventHotKey failed status=\(status)")
            return
        }
        installEventHandler()
        isRegistered = true
    }

    func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref); hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler); eventHandlerRef = nil
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
                let source = Unmanaged<CarbonChordSource>
                    .fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(eventRef)
                DispatchQueue.main.async {
                    switch Int(kind) {
                    case kEventHotKeyPressed:  source.onKeyDown?()
                    case kEventHotKeyReleased: source.onKeyUp?()
                    default: break
                    }
                }
                return noErr
            },
            eventTypes.count, &eventTypes, selfPtr, &eventHandlerRef)
    }

    deinit { stop() }
}
