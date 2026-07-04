// ReminderNotifier.swift (iOS)
//
// 0.12.15: iOS-side notifier that mirrors the Mac ReminderNotifier
// (StickySync/ReminderNotifier.swift). Same UNUserNotificationCenter
// wiring; UIKit instead of AppKit for the runtime.
//
// Design contract stays identical:
//   - Schedule UNCalendarNotificationTrigger keyed by reminder UUID.
//   - Ask for authorization on first schedule (in-context; not on
//     launch). Deny → reminder still in store, no notification.
//   - Delegate marks reminder as fired on delivery / tap.
//   - `rescheduleActive()` restores pending requests on app launch.
//
// When Phase B swaps the ReminderStore for a CloudKit-backed
// implementation, this class doesn't need to change — it consumes
// the protocol.

import Foundation
import UserNotifications
import NotesKit

@MainActor
final class ReminderNotifier: NSObject {

    private let store: ReminderStore
    private weak var noteStore: (AnyObject & NoteStore)?
    private let center = UNUserNotificationCenter.current()

    init(store: ReminderStore, noteStore: AnyObject & NoteStore) {
        self.store = store
        self.noteStore = noteStore
        super.init()
        center.delegate = self
    }

    func ensureAuthorized(then body: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { body(true) }
            case .denied:
                DispatchQueue.main.async { body(false) }
            case .notDetermined:
                Task { @MainActor in
                    do {
                        let granted = try await self.center.requestAuthorization(
                            options: [.alert, .sound, .badge])
                        body(granted)
                    } catch {
                        body(false)
                    }
                }
            @unknown default:
                DispatchQueue.main.async { body(false) }
            }
        }
    }

    func schedule(_ reminder: Reminder, noteBodyPreview: String) {
        let content = UNMutableNotificationContent()
        content.title = "StickySync reminder"
        content.body = ReminderNotifier.previewBody(from: noteBodyPreview)
        content.sound = .default
        // 0.12.x reserved: content.interruptionLevel = reminder.isUrgent
        //                    ? .timeSensitive : .active
        //   (needs the Time-Sensitive Notifications entitlement Sean
        //    will add in Xcode when back at the office Mac.)

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger)
        center.add(request) { error in
            if let error {
                NSLog("iOS ReminderNotifier: schedule failed: \(error)")
            }
        }
    }

    func cancel(_ reminderID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [reminderID.uuidString])
    }

    func rescheduleActive() {
        for reminder in store.activeReminders() {
            guard let note = noteStore?.note(id: reminder.noteID) else { continue }
            schedule(reminder, noteBodyPreview: note.content)
        }
    }

    /// Pure formatter — same shape as Mac. Kept nonisolated so tests
    /// can hit it without hopping to the main actor.
    nonisolated static func previewBody(from content: String) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return "Tap to open." }
        let limit = 80
        if firstLine.count <= limit { return firstLine }
        let idx = firstLine.index(firstLine.startIndex, offsetBy: limit)
        return String(firstLine[..<idx]) + "…"
    }
}

extension ReminderNotifier: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
        let reminderID = UUID(uuidString: notification.request.identifier)
        Task { @MainActor [weak self] in
            guard let self, let id = reminderID else { return }
            self.store.markFired(id, at: Date())
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let reminderID = UUID(uuidString: response.notification.request.identifier)
        Task { @MainActor [weak self] in
            defer { completionHandler() }
            guard let self, let id = reminderID else { return }
            self.store.markFired(id, at: Date())
            // Future: on tap, deep-link to the sticky. Deferred —
            // iOS scene navigation from a notification response is
            // its own dance.
        }
    }
}
