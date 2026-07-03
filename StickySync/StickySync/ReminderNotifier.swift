// ReminderNotifier.swift
//
// 0.12.3: wires the local reminder store to UNUserNotificationCenter.
// Schedules a UNCalendarNotificationTrigger per active reminder,
// keyed by the reminder's UUID so cancels work cleanly.
//
// Permission model (from the UX research pass): DO NOT request
// authorization on app launch (industry-standard "in-context ask").
// The first time the user confirms a /remind, we call
// `ensureAuthorized(then:)` which requests permission if needed;
// only if granted do we actually schedule. Denied → the reminder
// stays in the store but no notification is scheduled. User can
// re-enable in System Settings and future reminders will work.
//
// Notification content:
//   title = "StickySync reminder"
//   body  = first line of the note content (truncated ~80 chars)
//     — captured at schedule time. Phase A doesn't live-update if
//       the note edits later; that's Phase B territory.
//
// On fire, the delegate marks the reminder as `fired` in the store.
// Chrome bell (0.12.5) reads that flag to show past-due state.

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

    /// Ensure we've been granted permission; then run `body` with
    /// a Bool indicating whether we can schedule. Safe to call
    /// repeatedly — after the first grant/deny it just reads the
    /// current setting.
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

    /// Schedule (or reschedule) the notification for a reminder.
    /// Idempotent — replaces any prior pending request with the
    /// same UUID.
    func schedule(_ reminder: Reminder, noteBodyPreview: String) {
        let content = UNMutableNotificationContent()
        content.title = "StickySync reminder"
        content.body = ReminderNotifier.previewBody(from: noteBodyPreview)
        content.sound = .default
        // 0.12.4 will honor isUrgent by promoting to
        // .timeSensitive (needs the entitlement). Phase A always
        // ships .active — the OS default.
        // content.interruptionLevel = reminder.isUrgent ? .timeSensitive : .active

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
                NSLog("ReminderNotifier: schedule failed: \(error)")
            }
        }
    }

    /// Cancel a pending notification (user cleared the reminder or
    /// deleted the note).
    func cancel(_ reminderID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [reminderID.uuidString])
    }

    /// On app launch: walk active reminders, ensure each has a
    /// pending request. Recovers from a rare state where the OS
    /// lost our pending list (crash, restore, etc.).
    func rescheduleActive() {
        for reminder in store.activeReminders() {
            guard let note = noteStore?.note(id: reminder.noteID) else { continue }
            schedule(reminder, noteBodyPreview: note.content)
        }
    }

    /// Note body → first non-empty line, up to ~80 chars, with
    /// trailing ellipsis if truncated. Used as the notification's
    /// body so the user knows which sticky reminded them.
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

    /// Show the banner + play sound even when the app is
    /// foregrounded. Without this override, foreground reminders
    /// are silent.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
        // Mark fired on the store — chrome bell (0.12.5) will read
        // this to show past-due state. Fire-time is nonisolated,
        // hop back to main.
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
            // Future: on tap, open the associated sticky. Deferred
            // to a later ship — needs a URL scheme or per-note
            // openWindow lookup keyed by the reminder's noteID.
        }
    }
}
