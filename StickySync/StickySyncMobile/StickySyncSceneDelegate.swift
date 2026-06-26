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
}
