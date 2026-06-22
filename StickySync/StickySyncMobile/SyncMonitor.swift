import SwiftUI
import CoreData
import Combine

/// Surfaces CloudKit sync state for a calm status line, so an eventual-consistency
/// delay reads as "Syncing…" rather than "my note is lost."
///
/// Listens to the `NSPersistentCloudKitContainer` event stream — the same events
/// the store logs as "export ok" — and reduces them: `syncing` while any
/// import/export is in flight, otherwise `synced` with the last finish time.
@MainActor
final class SyncMonitor: ObservableObject {
    enum State: Equatable {
        case idle
        case syncing
        case synced(Date)
        case error
    }

    @Published private(set) var state: State = .idle

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
            active.insert(event.identifier)          // an import/export just started
        } else {
            active.remove(event.identifier)          // …and now finished
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
