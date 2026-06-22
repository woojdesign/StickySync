import Foundation
import CoreData
import Combine

/// Tracks CloudKit sync state from the `NSPersistentCloudKitContainer` event
/// stream — the same events the store logs as "export ok" — for the menu-bar
/// status line. A plain observer: read `state` on the main thread (the menu
/// rebuilds on open, so it always reflects the latest).
final class SyncMonitor {
    enum State {
        case idle
        case syncing
        case synced(Date)
        case error
    }

    private(set) var state: State = .idle

    private var active = Set<UUID>()
    private var lastEnd: Date?
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

        if event.endDate == nil {
            active.insert(event.identifier)
        } else {
            active.remove(event.identifier)
            lastEnd = event.endDate
            if event.error != nil { state = .error; return }
        }

        if !active.isEmpty {
            state = .syncing
        } else if let lastEnd {
            state = .synced(lastEnd)
        }
    }
}
