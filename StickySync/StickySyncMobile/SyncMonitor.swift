import SwiftUI
import CoreData
import Combine

/// Surfaces CloudKit sync state for a calm status line. On launch we start
/// in `.checking` because the truth is we don't yet know whether something's
/// pending on the server — NSPersistentCloudKitContainer doesn't fire an
/// import event immediately; it relies on silent pushes that may have been
/// held while the app was closed. Showing "Synced" before the first import
/// confirmation would be a lie.
///
/// Listens to the `NSPersistentCloudKitContainer` event stream — the same
/// events the store logs as "export ok" — and reduces them.
@MainActor
final class SyncMonitor: ObservableObject {
    enum State: Equatable {
        case checking
        case idle
        case syncing
        case synced(Date)
        case error
    }

    @Published private(set) var state: State = .checking

    private var active = Set<UUID>()
    private var lastEnd: Date?
    private var sawFirstImport = false
    private var cancellable: AnyCancellable?
    /// Fall back to `.synced` after this long even without an import event,
    /// so the indicator doesn't get stuck in `.checking` forever.
    private let checkingTimeoutSeconds: TimeInterval = 30

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.handle(note) }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(checkingTimeoutSeconds * 1_000_000_000))
            if case .checking = self.state {
                self.state = .synced(self.lastEnd ?? Date())
            }
        }
    }

    private func handle(_ note: Notification) {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else { return }

        let isImport = (event.type == .import)
        let isStart = event.endDate == nil

        if isStart {
            active.insert(event.identifier)
        } else {
            active.remove(event.identifier)
            lastEnd = event.endDate
            if event.error != nil { state = .error; return }
            if isImport { sawFirstImport = true }
        }

        if !active.isEmpty {
            state = .syncing
        } else if sawFirstImport, let lastEnd {
            state = .synced(lastEnd)
        } else if case .checking = state {
            // Stay in checking — we've only seen exports, not yet been
            // told there's nothing waiting for us.
        } else if let lastEnd {
            state = .synced(lastEnd)
        }
    }
}
