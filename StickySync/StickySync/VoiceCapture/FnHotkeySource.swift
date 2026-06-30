// FnHotkeySource.swift
//
// Fn-key global hotkey source using NSEvent.addGlobalMonitorForEvents.
// Requires Accessibility permission (System Settings → Privacy &
// Security → Accessibility). Carbon's RegisterEventHotKey doesn't
// support Fn (the modifier mask doesn't include it), so this is the
// only way to bind Fn as a hotkey.
//
// **Gesture: hold-to-talk.** Press Fn → onKeyDown. Release Fn →
// onKeyUp. The HotkeyController in `.fn` mode maps these directly to
// .started / .stopped so the recording lifecycle follows the key.
//
// **Fn-alone vs Fn+other-key.** Any non-Fn key pressed during a
// Fn-down window pollutes the session: we fire onKeyUp immediately
// (canceling the recording in progress) and suppress the actual
// Fn-up emit. Without this, pressing Fn+brightness during a
// recording would adjust brightness AND incorrectly continue the
// recording past the user's intent.

import AppKit
import Carbon.HIToolbox   // for kVK_Function = 63
import OSLog

final class FnHotkeySource: HotkeySource {

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    /// `NSEvent.addGlobalMonitorForEvents` only fires for events
    /// delivered to OTHER apps. When the user is focused on a
    /// sticky (StickySync's own window), events go to that text
    /// view and never hit the global monitor — Fn wouldn't trigger
    /// (Sean's 0.8.8 log: events arrived cleanly when outside the
    /// app, were invisible when inside a sticky). Need a local
    /// monitor in parallel for the in-app path.
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var detector = FnHoldDetector()

    func start() {
        // The accessibility prompt is a one-time system dialog. We
        // request without forcing it here (caller decides when to
        // prompt); if not granted, the global monitor silently
        // delivers no events. The local monitor doesn't need
        // accessibility — it's events delivered to our own app.
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.processEvent(event, scope: "global")
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.processEvent(event, scope: "local")
            // Pass through so the user's normal typing isn't
            // consumed — the only thing we react to is Fn alone,
            // which doesn't insert anything anyway.
            return event
        }
        SyncLog.voice.info("fn: monitors installed (accessibility \(AXIsProcessTrusted() ? "granted" : "NOT granted", privacy: .public))")
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        detector.reset()
    }

    private func processEvent(_ event: NSEvent, scope: String) {
        SyncLog.voice.info("fn[\(scope, privacy: .public)]: event type=\(event.type.rawValue, privacy: .public) keyCode=\(event.keyCode, privacy: .public) modifiers=\(event.modifierFlags.rawValue, privacy: .public)")
        for emit in detector.handle(event) {
            switch emit {
            case .keyDown:
                SyncLog.voice.info("fn: → keyDown")
                onKeyDown?()
            case .keyUp:
                SyncLog.voice.info("fn: → keyUp")
                onKeyUp?()
            }
        }
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

/// Pure state machine for Fn hold-to-talk gesture with pollution
/// detection — testable without NSEvent.
///
/// Emits a sequence of "down" / "up" events per Fn press cycle:
///   - clean Fn-down → Fn-up:  [.keyDown, .keyUp]
///   - Fn-down → other key → Fn-up:  [.keyDown, .keyUp] (the second
///     fires on the other-key press, canceling the recording mid-
///     flight). The actual Fn-up is silent because we already
///     stopped.
///   - Spurious flags changes (other modifiers transitioning, etc.)
///     are no-ops.
struct FnHoldDetector {
    enum Emit { case keyDown, keyUp }

    /// Track whether Fn is currently pressed (per our state, not
    /// necessarily the OS state — we may have already emitted .keyUp
    /// due to pollution while the user is still physically holding).
    private var fnHeld = false
    /// Track whether we've already emitted .keyUp for the current
    /// Fn-down window (pollution path). Suppresses the duplicate
    /// .keyUp on the actual Fn-up.
    private var alreadyStopped = false

    mutating func reset() {
        fnHeld = false
        alreadyStopped = false
    }

    /// Feed an NSEvent. Returns the sequence of emissions (often
    /// empty, occasionally one or two) the wrapper should forward to
    /// the caller.
    mutating func handle(_ event: NSEvent) -> [Emit] {
        switch event.type {
        case .flagsChanged:
            let fnNowSet = event.modifierFlags.contains(.function)
            if fnNowSet && !fnHeld {
                // Fn-down transition. Hold-to-talk starts here.
                fnHeld = true
                alreadyStopped = false
                return [.keyDown]
            }
            if !fnNowSet && fnHeld {
                // Fn-up transition. Emit .keyUp unless we already
                // emitted it on a polluted .keyDown event.
                fnHeld = false
                let emit: [Emit] = alreadyStopped ? [] : [.keyUp]
                alreadyStopped = false
                return emit
            }
            return []
        case .keyDown:
            // A non-Fn key fired. If we're inside a Fn-down window,
            // cancel the recording — emit .keyUp now, suppress the
            // duplicate on the actual Fn-up.
            if fnHeld && !alreadyStopped {
                alreadyStopped = true
                return [.keyUp]
            }
            return []
        case .keyUp:
            // Backup path for Fn release: some keyboards/macOS
            // versions emit a .keyUp with keyCode 63 (kVK_Function)
            // instead of a clean .flagsChanged transition. Sean's
            // 0.8.7 report: hold worked but release didn't stop,
            // strongly suggests the .flagsChanged for Fn-up isn't
            // arriving on his MBA. Treat keyCode 63 keyUp the same
            // as a Fn-up flagsChanged.
            if event.keyCode == 63 && fnHeld {
                fnHeld = false
                let emit: [Emit] = alreadyStopped ? [] : [.keyUp]
                alreadyStopped = false
                return emit
            }
            return []
        default:
            return []
        }
    }
}
