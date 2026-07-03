// BetaAwareUpdaterDelegate.swift
//
// 0.12.13: bridges `BetaChannel.isEnabled` into Sparkle's per-check
// hooks. `SPUUpdaterDelegate.feedURLString(for:)` and
// `.allowedChannels(for:)` are the officially supported way to
// change feed/channel at runtime; UserDefaults keys are read only
// at controller init.
//
// Wired from AppDelegate as the updaterDelegate passed to
// SPUStandardUpdaterController. On every Check for Updates:
//   - If beta channel is on: return the beta-feed appcast URL +
//     ["beta"] as allowed channels → Sparkle finds prereleases.
//   - Otherwise: return nil (Sparkle uses SUFeedURL from Info.plist,
//     which points at the stable feed) + no channel filter.

import Foundation

#if canImport(Sparkle)
import Sparkle

final class BetaAwareUpdaterDelegate: NSObject, SPUUpdaterDelegate {

    func feedURLString(for updater: SPUUpdater) -> String? {
        BetaChannel.isEnabled ? BetaChannel.feedURL : nil
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        BetaChannel.isEnabled ? ["beta"] : []
    }
}
#endif
