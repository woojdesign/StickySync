import SwiftUI
import CoreData
import Combine

/// iOS counterpart of the Mac `SyncMonitor` — same state machine, same
/// state-mapping rules, just published as an `ObservableObject` so
/// SwiftUI's `@StateObject` can wire it directly into a view.
///
/// See `StickySync/SyncMonitor.swift` for the design rationale. The
/// short version: Bear's pattern — **silent success, loud failure**.
/// `.harmony` renders nothing; the indicator only appears for
/// `.syncing`, `.offline`, or `.error(_)`.
@MainActor
final class SyncMonitor: ObservableObject {
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

    @Published private(set) var state: State = .harmony

    private var active = Set<UUID>()
    private var cancellable: AnyCancellable?

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.handle(note) }
    }

    private func handle(_ note: Notification) {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else { return }

        // Ignore `.setup` (one-time bootstrap, not ongoing sync).
        guard event.type != .setup else { return }

        let isStart = event.endDate == nil

        if isStart {
            active.insert(event.identifier)
        } else {
            active.remove(event.identifier)
            if let error = event.error {
                state = classify(error)
                return
            }
        }

        let next: State = active.isEmpty ? .harmony : .syncing
        if next != state {
            state = next
        }
    }

    private func classify(_ error: Error) -> State {
        let nsError = error as NSError
        let code: Int
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == "CKErrorDomain" {
            code = underlying.code
        } else if nsError.domain == "CKErrorDomain" {
            code = nsError.code
        } else {
            return .error(.unknown)
        }
        switch code {
        case 3:  return .offline
        case 4:  return .offline
        case 9:  return .error(.account)
        case 25: return .error(.quota)
        default: return .error(.unknown)
        }
    }
}
