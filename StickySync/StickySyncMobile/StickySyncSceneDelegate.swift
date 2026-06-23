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

final class StickySyncSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        // Forward the accept to the same CloudKitNoteStore the SwiftUI side
        // is reading from, so the new shared note appears in the list.
        guard let ckStore = NoteStoreProvider.shared as? CloudKitNoteStore else {
            NSLog("StickySync: accept-share callback fired but store isn't CloudKitNoteStore")
            return
        }
        Task {
            do {
                try await ckStore.acceptShareInvitation(metadata: cloudKitShareMetadata)
            } catch {
                NSLog("StickySync: accept share failed: \(error)")
            }
        }
    }
}
