// HotkeySource.swift
//
// Abstraction over the underlying global-hotkey backend, so the
// HotkeyController can switch between modes (Carbon-based chord or
// NSEvent-based Fn) without the rest of the voice-capture pipeline
// caring about how the chord is detected.

import Foundation

/// One source of "hotkey toggle events." Implementations:
///   - `CarbonChordSource`: Carbon RegisterEventHotKey for a chord
///     like ⌥V. No accessibility permission required.
///   - `FnHotkeySource`: NSEvent global monitor for the Fn modifier
///     alone. Requires accessibility permission.
protocol HotkeySource: AnyObject {
    /// Called from the platform layer when the configured key fires.
    /// The coordinator wires this to its state machine.
    var onKeyDown: (() -> Void)? { get set }
    /// Called on key-up. Most sources don't fire this; included so
    /// future hold-to-talk modes can attach here.
    var onKeyUp: (() -> Void)? { get set }
    func start()
    func stop()
}
