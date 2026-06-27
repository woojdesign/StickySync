import Foundation
import CoreData
import Combine

/// Tracks CloudKit sync state from the `NSPersistentCloudKitContainer` event
/// stream — the same events the store logs as "export ok" — for the menu-bar
/// status line.
///
/// On launch we start in `.checking` rather than `.idle`/`.synced` because the
/// truth is we *don't yet know* whether anything's pending on the server side.
/// NSPersistentCloudKitContainer doesn't immediately fire an import event;
/// it relies on silent pushes that may have been held while the app was
/// closed. Until we see the first import-ended event (or hit a hard timeout),
/// telling the user "Synced" would be a lie. `.checking` resolves to
/// `.synced` once a real signal comes in, or to a fallback synced state at
/// timeout.
final class SyncMonitor {
    enum State {
        case checking         // launched, haven't seen an import event yet
        case idle             // post-resolution quiet
        case syncing          // an in-flight operation
        case synced(Date)
        case error
    }

    private(set) var state: State = .checking

    private var active = Set<UUID>()
    private var lastEnd: Date?
    private var sawFirstImport = false
    private var cancellable: AnyCancellable?
    /// Hard timeout: if we've shown "Checking…" for this long without an
    /// import event, fall back to `.synced` so the indicator doesn't lie
    /// in the *other* direction (looking stuck forever).
    private let checkingTimeoutSeconds: TimeInterval = 30

    /// Posted on state changes — observers (menu bar status item, dock,
    /// the iOS list view) rebuild on each fire.
    static let stateDidChange = Notification.Name("design.wooj.StickySync.syncStateDidChange")

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.handle(note) }

        // Kick off the timeout. If the framework never fires an import
        // event in N seconds, we stop showing "Checking…" and assume
        // we're up to date — the worst case is the user gets the same
        // honest-but-imperfect "Synced" they saw before this change.
        DispatchQueue.main.asyncAfter(deadline: .now() + checkingTimeoutSeconds) { [weak self] in
            guard let self, case .checking = self.state else { return }
            self.state = .synced(self.lastEnd ?? Date())
            self.publishStateChange()
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
            if event.error != nil {
                state = .error
                publishStateChange()
                return
            }
            if isImport { sawFirstImport = true }
        }

        if !active.isEmpty {
            state = .syncing
        } else if sawFirstImport, let lastEnd {
            // We've actually heard back on the import side at least once;
            // this is "real" synced, not a guess.
            state = .synced(lastEnd)
        } else if case .checking = state {
            // Export-only event before the first import — stay in
            // checking so the indicator continues to read honestly
            // ("we sent something, but we haven't confirmed there's
            // nothing waiting for us").
        } else if let lastEnd {
            state = .synced(lastEnd)
        }
        publishStateChange()
    }

    private func publishStateChange() {
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }
}
