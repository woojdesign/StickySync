// BetaChannel.swift
//
// 0.11.1: opt-in/out of the Sparkle beta channel via UserDefaults.
// Sparkle reads SUFeedURL + SUAllowedChannels from UserDefaults
// on every update check, so toggling this at runtime picks up on
// the next check without a restart.
//
// Wiring (in StickySync app menu → Beta Channel):
//   - When enabled:
//       SUFeedURL         = beta appcast URL (fixed rolling tag)
//       SUAllowedChannels = ["beta"]
//   - When disabled: both keys removed (Sparkle falls back to
//     Info.plist's SUFeedURL → stable feed).
//
// This is intentionally opt-in per-Mac, not per-user. If Sean
// wants his home Mac on beta and his office Mac on stable, he
// toggles each one.

import Foundation

enum BetaChannel {
    static let feedURL = "https://github.com/woojdesign/StickySync/releases/download/beta-feed/appcast.xml"
    private static let suFeedKey = "SUFeedURL"
    private static let suChannelsKey = "SUAllowedChannels"

    static var isEnabled: Bool {
        (UserDefaults.standard.stringArray(forKey: suChannelsKey) ?? [])
            .contains("beta")
    }

    static func setEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        if enabled {
            defaults.set(feedURL, forKey: suFeedKey)
            defaults.set(["beta"], forKey: suChannelsKey)
        } else {
            defaults.removeObject(forKey: suFeedKey)
            defaults.removeObject(forKey: suChannelsKey)
        }
    }
}
