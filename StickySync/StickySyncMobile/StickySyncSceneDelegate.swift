// StickySyncSceneDelegate.swift
//
// SwiftUI-only apps don't get `windowScene(_:userDidAcceptCloudKitShareWith:)`
// for free — the callback drops on the floor. This delegate class, wired into
// Info.plist's UIApplicationSceneManifest, restores it so users can accept
// CKShare invitations tapped from iMessage / Mail. ([Apple forum 656625]).
//
// Beyond the share-accept callback, this is a thin delegate — we let SwiftUI
// own scene lifecycle.

import UIKit
import CloudKit
import NotesKit

extension Notification.Name {
    /// Posted with the arrived `Note` as the object once an incoming share
    /// has been accepted and the new note shows up locally. NotesListView
    /// listens and opens the editor for it.
    static let didAcceptSharedNote = Notification.Name("StickySync.didAcceptSharedNote")
}

final class StickySyncSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        guard let ckStore = NoteStoreProvider.shared as? CloudKitNoteStore else {
            NSLog("StickySync: accept-share callback fired but store isn't CloudKitNoteStore")
            return
        }
        Task { @MainActor in
            do {
                let arrived = try await ckStore.acceptShareInvitation(metadata: cloudKitShareMetadata)
                if let arrived {
                    // Hand the arrived note to the SwiftUI side so the list
                    // can route into the editor — the user's eyes are on
                    // Messages right before this fires; we want them to land
                    // on the note itself, not the list.
                    NotificationCenter.default.post(name: .didAcceptSharedNote, object: arrived)
                }
            } catch {
                NSLog("StickySync: accept share failed: \(error)")
            }
        }
    }

    /// Cold launch from a Universal Link tap. iOS hands us the originating
    /// NSUserActivity via the connection options; if it's a browsing-web
    /// activity for our share landing page, forward it through the same
    /// universal-link path the warm continue handler uses.
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let userActivity = connectionOptions.userActivities.first(where: {
            $0.activityType == NSUserActivityTypeBrowsingWeb
        }) {
            handleUniversalLink(userActivity)
        }
    }

    /// Warm Universal Link tap — the app is already running, the user comes
    /// in via a tapped link in Safari / Mail / etc.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleUniversalLink(userActivity)
    }

    private func handleUniversalLink(_ userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        routeShareURL(url)
    }

    /// Custom URL scheme handler — `stickysync://share?ck=…`. Used as the
    /// in-page "Open the sticky →" tap target so the landing page has a
    /// deterministic open-the-app trigger that works from the same Safari
    /// session as the landing page itself (where Universal Links don't
    /// re-fire).
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts where context.url.scheme == "stickysync" {
            routeShareURL(context.url)
        }
    }

    /// Shared accept path for both Universal Links and the `stickysync://`
    /// custom URL scheme. Extracts the `ck=` query parameter (the iCloud
    /// share URL) and runs it through `CloudKitNoteStore.acceptShare(from:)`.
    private func routeShareURL(_ url: URL) {
        guard let ckStore = NoteStoreProvider.shared as? CloudKitNoteStore,
              let ckString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ck" })?.value,
              let ckURL = URL(string: ckString) else {
            NSLog("StickySync: incoming share URL missing or malformed ck= param: \(url)")
            return
        }
        Task { @MainActor in
            do {
                let arrived = try await ckStore.acceptShare(from: ckURL)
                if let arrived {
                    NotificationCenter.default.post(name: .didAcceptSharedNote, object: arrived)
                }
            } catch {
                NSLog("StickySync: incoming share accept failed: \(error)")
            }
        }
    }
}
