// CloudShareSheet.swift
//
// SwiftUI wrapper around `UICloudSharingController`. Presents Apple's stock
// share-with-people UI (recipient picker, permissions, "Stop Sharing"), pre-
// configured with a CKShare we created via `CloudKitNoteStore.share(_:)`.
//
// We pre-create the share rather than using `UICloudSharingController`'s
// lazy-create initializer, because the lazy path is buggy when wrapped in
// SwiftUI (a known issue — the controller sometimes never fires its
// preparation handler). Pre-creating then handing in via
// `init(share:container:)` always works.

import SwiftUI
import UIKit
import CloudKit
import NotesKit

struct CloudShareSheet: UIViewControllerRepresentable {
    let note: Note

    /// Called when the sheet dismisses; carries the resulting share (nil if
    /// the user cancelled and we should treat it as "still not shared").
    var onDismiss: (CKShare?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UIViewController {
        // Sentinel controller — we swap in the real one once the share has
        // been prepared. This lets us present synchronously from SwiftUI.
        let host = UIViewController()
        host.view.backgroundColor = .clear
        context.coordinator.host = host

        guard let ckStore = NoteStoreProvider.shared as? CloudKitNoteStore else {
            context.coordinator.dismiss(with: nil)
            return host
        }

        Task { @MainActor in
            do {
                let (share, container) = try await ckStore.share(note)
                let sharingController = UICloudSharingController(share: share, container: container)
                sharingController.delegate = context.coordinator
                sharingController.availablePermissions = [.allowReadWrite, .allowPrivate]
                context.coordinator.share = share
                // Present from the host VC, which SwiftUI has placed in the
                // hierarchy by now.
                host.present(sharingController, animated: true)
            } catch {
                NSLog("StickySync: failed to prepare share — \(error)")
                context.coordinator.dismiss(with: nil)
            }
        }

        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: (CKShare?) -> Void
        weak var host: UIViewController?
        var share: CKShare?

        init(onDismiss: @escaping (CKShare?) -> Void) {
            self.onDismiss = onDismiss
        }

        func dismiss(with share: CKShare?) {
            host?.dismiss(animated: true) { [weak self] in self?.onDismiss(share) }
        }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            NSLog("StickySync: share save failed — \(error)")
            dismiss(with: nil)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            (share?[CKShare.SystemFieldKey.title] as? String) ?? "Note"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            dismiss(with: share)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // Owner stopped sharing OR participant left. The framework has
            // already removed our access; just refresh.
            dismiss(with: nil)
        }
    }
}
