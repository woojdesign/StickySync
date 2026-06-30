// FnHotkeySource.swift
//
// Fn-key global hotkey source using NSEvent.addGlobalMonitorForEvents.
// Requires Accessibility permission (System Settings → Privacy &
// Security → Accessibility). Carbon's RegisterEventHotKey doesn't
// support Fn (the modifier mask doesn't include it), so this is the
// only way to bind Fn as a hotkey.
//
// **Fn-alone detection** — Apple's own Dictation uses a Fn-tap
// shortcut, and we copy the pattern: a Fn-down followed by a Fn-up
// with NO other key pressed in between counts as a "Fn tap" and
// fires the toggle. Fn pressed alongside another key (Fn+brightness,
// Fn+arrow, etc.) is silent. Otherwise pressing brightness up would
// accidentally toggle voice capture.
//
// State machine pure helper `FnTapDetector` is testable without
// NSEvent; the wrapper class plumbs real events into it.

import AppKit

final class FnHotkeySource: HotkeySource {

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var monitor: Any?
    private var detector = FnTapDetector()

    func start() {
        // The accessibility prompt is a one-time system dialog. We
        // request without forcing it here (caller decides when to
        // prompt); if not granted, the global monitor silently
        // delivers no events. Better than crashing or surprising
        // the user with an unsolicited permission dialog.
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return }
            let result = self.detector.handle(event)
            switch result {
            case .fnTap:    self.onKeyDown?()   // each tap toggles
            case .none:     break
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        detector.reset()
    }

    /// Request Accessibility permission with the standard system
    /// prompt. Call before `start()` when the user opts in to Fn
    /// mode. Returns true if already trusted or if the user grants
    /// during the prompt.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    deinit { stop() }
}

/// Pure state machine for "Fn pressed alone" vs "Fn pressed with
/// another key" — testable without NSEvent.
///
/// The intent is to fire ONLY on a clean Fn-tap (down + up with no
/// other key in between). Fn used as a modifier alongside something
/// else (Fn+brightness, Fn+arrow, etc.) is silent.
struct FnTapDetector {
    enum Result { case none, fnTap }

    /// Track whether we're inside a Fn-down window. Reset on Fn-up.
    private var fnHeld = false
    /// Was a non-Fn key pressed during the current Fn-down? If yes,
    /// don't fire the tap on Fn-up.
    private var otherKeyDuringFn = false

    mutating func reset() {
        fnHeld = false
        otherKeyDuringFn = false
    }

    /// Feed an NSEvent. Returns whether the event completes a clean
    /// Fn-tap (in which case the caller should fire the toggle).
    mutating func handle(_ event: NSEvent) -> Result {
        switch event.type {
        case .flagsChanged:
            let fnNowSet = event.modifierFlags.contains(.function)
            if fnNowSet && !fnHeld {
                // Fn-down transition.
                fnHeld = true
                otherKeyDuringFn = false
                return .none
            }
            if !fnNowSet && fnHeld {
                // Fn-up transition.
                let wasCleanTap = !otherKeyDuringFn
                fnHeld = false
                otherKeyDuringFn = false
                return wasCleanTap ? .fnTap : .none
            }
            return .none
        case .keyDown:
            // A regular key fired. If we're inside a Fn-down window,
            // mark it as polluted so the eventual Fn-up doesn't tap.
            if fnHeld { otherKeyDuringFn = true }
            return .none
        default:
            return .none
        }
    }
}
