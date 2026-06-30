// VoiceCaptureSettings.swift
//
// User-facing voice-capture preferences. Backed by UserDefaults so
// the user's choice survives relaunch (and Sparkle update). Shared
// surface for the status-item menu and the AppDelegate boot path.

import Foundation

enum VoiceCaptureSettings {
    private static let hotkeyModeKey = "wooj.voiceCapture.hotkeyMode"

    static var hotkeyMode: HotkeyController.Mode {
        get {
            let raw = UserDefaults.standard.string(forKey: hotkeyModeKey) ?? "chord"
            return HotkeyController.Mode(rawValue: raw) ?? .chord
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: hotkeyModeKey)
            NotificationCenter.default.post(name: .voiceHotkeyModeDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted whenever the user picks a new hotkey mode. AppDelegate
    /// listens and re-configures the live HotkeyController.
    static let voiceHotkeyModeDidChange = Notification.Name("wooj.voice.hotkeyModeDidChange")
}
