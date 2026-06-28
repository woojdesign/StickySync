import Foundation
import CoreData
import Combine

/// Tracks CloudKit sync state from the `NSPersistentCloudKitContainer` event
/// stream, then collapses it into the four user-facing states the indicator
/// renders. Designed to follow Bear's pattern — **silent success, loud
/// failure**:
///
///   - `.harmony` is the default and *renders nothing*. The absence of any
///     indicator IS the success state.
///   - `.syncing` appears only while an operation is in flight.
///   - `.offline` and `.error(_)` surface real failure modes with named
///     copy so the user knows the cause + the fix.
///
/// Background: round-2 research surveyed Bear, Things, Drafts, iA Writer,
/// Ulysses, Craft, Apple Notes, and Notion. Every respected app skips the
/// "Synced" badge entirely (and skips per-note timestamps). Showing
/// "Synced" was overstating what we can actually verify — and showing
/// "Checking iCloud…" then timing out to "Synced" was a lie in both
/// directions. Now we stay quiet unless we have positive info that
/// something is wrong or in progress.
///
/// What we deliberately *don't* surface:
///   - "Last synced HH:MM" — exposes us to "you lied" failures (push
///     succeeded at 3:42, edit at 3:43 not yet uploaded → timestamp is
///     now misleading). No respected app does this.
///   - A `.checking` state on launch — we don't know what we don't know.
///   - An `.idle` state — was dead code.
///
/// What we *do* know reliably (per Apple's NSPersistentCloudKitContainer
/// Event API):
///   - When operations start (`endDate == nil`) and end (`endDate != nil`).
///   - Whether they succeeded (`succeeded` flag + `error == nil`).
///   - The error's kind via CKError code, when one is present.
final class SyncMonitor {
    enum State: Equatable {
        case harmony
        case syncing
        case offline
        case error(Kind)

        enum Kind: String, Equatable {
            case network
            case account
            case quota
            case unknown
        }
    }

    private(set) var state: State = .harmony

    private var active = Set<UUID>()
    private var cancellable: AnyCancellable?

    /// Posted on state changes — observers (menu bar status item, the iOS
    /// list view) rebuild on each fire.
    static let stateDidChange = Notification.Name("design.wooj.StickySync.syncStateDidChange")

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.handle(note) }
    }

    private func handle(_ note: Notification) {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else { return }

        // Ignore `.setup` events for the user-facing glyph — they're the
        // one-time bootstrap, not ongoing sync. Round-2 research: every
        // shipping CloudKitSyncMonitor consumer ignores `.setup` for UX.
        guard event.type != .setup else { return }

        let isStart = event.endDate == nil

        if isStart {
            active.insert(event.identifier)
        } else {
            active.remove(event.identifier)
            if let error = event.error {
                state = classify(error)
                publishStateChange()
                return
            }
        }

        // No error path. If anything's in flight, show .syncing.
        // Otherwise return to .harmony — the renderer hides the
        // indicator entirely, which is the success signal.
        let next: State = active.isEmpty ? .harmony : .syncing
        if next != state {
            state = next
            publishStateChange()
        }
    }

    /// Map a CloudKit framework error to one of the four named user-
    /// facing failure modes. The codes here are the ones Apple's CKError
    /// enum exposes; we cover the cases that have actionable user fixes
    /// (sign in, free space, get back online) and fold everything else
    /// into `.unknown` so the copy stays accurate.
    private func classify(_ error: Error) -> State {
        let nsError = error as NSError
        // CKError lives in the `CKErrorDomain`, but Core Data wraps it,
        // so check both the userInfo for an underlying CKError and the
        // top-level code.
        let code: Int
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == "CKErrorDomain" {
            code = underlying.code
        } else if nsError.domain == "CKErrorDomain" {
            code = nsError.code
        } else {
            return .error(.unknown)
        }

        // CKError code numbers per Apple's CloudKit headers — kept as
        // raw ints to avoid the framework import here.
        switch code {
        case 3:  return .offline           // .networkUnavailable
        case 4:  return .offline           // .networkFailure
        case 9:  return .error(.account)   // .notAuthenticated
        case 25: return .error(.quota)     // .quotaExceeded
        default: return .error(.unknown)
        }
    }

    private func publishStateChange() {
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }
}
