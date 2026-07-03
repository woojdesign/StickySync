// Reminder.swift
//
// 0.12.0: sticky-scoped reminder — one per note, attached via note.id.
// Phase A ships with a UserDefaults-backed local-only store while
// Sean's away and we can't do the CloudKit schema redeploy. Phase B
// swaps this out for a NotesKit-backed CloudKit-synced storage; the
// value type + protocol stay the same so callers don't churn.
//
// Sean's design contract (see project_reminders_design memory):
//   - One reminder per note. Setting a new one replaces the old.
//   - Reminder is metadata on the note, not text inside it. When
//     the /remind popover confirms, the /remind line is stripped
//     from the note body.
//   - `fired` marks completion. Cleared on fire → the chrome bell
//     disappears. Snooze re-sets `fireAt` and clears `fired`.
//   - `firedAt` is the LWW tiebreaker for cross-device fire-once
//     (Phase B). Whichever device fires first stamps firedAt; the
//     others see the sync and cancel their pending notification.

import Foundation

/// Sticky-scoped reminder. Immutable id + noteID pairing; all other
/// fields mutate through the store.
public struct Reminder: Codable, Equatable, Identifiable {
    public let id: UUID
    public let noteID: UUID
    public var fireAt: Date
    /// 0.12.4 will honor this (needs the Time-Sensitive Notifications
    /// entitlement Sean has to add in Xcode). Phase A stores the
    /// bit but always schedules `.active` in the notification layer.
    public var isUrgent: Bool
    /// Set true when the notification has been delivered or the user
    /// cleared it. The chrome bell hides when fired.
    public var fired: Bool
    /// LWW tiebreaker for cross-device fire-once (Phase B). Local-
    /// only ships in Phase A ignore it beyond the fire flag itself.
    public var firedAt: Date?

    public init(id: UUID = UUID(),
                noteID: UUID,
                fireAt: Date,
                isUrgent: Bool = false,
                fired: Bool = false,
                firedAt: Date? = nil) {
        self.id = id
        self.noteID = noteID
        self.fireAt = fireAt
        self.isUrgent = isUrgent
        self.fired = fired
        self.firedAt = firedAt
    }

    /// Convenience: is this reminder scheduled for the future and
    /// hasn't fired yet? Used by the chrome-bell state resolver.
    public var isActive: Bool {
        !fired && fireAt > Date()
    }
}

/// Store contract. Both the Phase A local-only implementation and
/// the Phase B CloudKit-backed one conform.
///
/// Sticky-scoped means "at most one reminder per note" — the store
/// enforces this on `set`. Setting a new reminder for a note that
/// already has one replaces the old.
public protocol ReminderStore {
    /// The reminder attached to `noteID`, or nil if none.
    func reminder(for noteID: UUID) -> Reminder?
    /// All active (unfired, future) reminders — for scheduling
    /// notifications on launch, showing counts, etc.
    func activeReminders() -> [Reminder]
    /// Set the reminder for a note. Replaces any existing one.
    func set(_ reminder: Reminder)
    /// Clear the reminder for a note (user tapped Clear, or the note
    /// was deleted).
    func clear(for noteID: UUID)
    /// Mark a reminder as fired (with a timestamp for LWW).
    func markFired(_ reminderID: UUID, at date: Date)
}

/// Phase A: keyed by "reminder.<noteID>" in UserDefaults.suite
/// (`design.wooj.StickySync.reminders` — separate from the app's
/// main defaults so wiping it doesn't nuke user prefs).
///
/// Not synced. Fine for single-device testing while Sean's away;
/// Phase B swaps for a NotesKit-backed store once schema is
/// redeployed.
public final class UserDefaultsReminderStore: ReminderStore {
    private let defaults: UserDefaults
    private let keyPrefix = "reminder."

    public init(suiteName: String = "design.wooj.StickySync.reminders") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public func reminder(for noteID: UUID) -> Reminder? {
        guard let data = defaults.data(forKey: keyPrefix + noteID.uuidString) else {
            return nil
        }
        return try? JSONDecoder().decode(Reminder.self, from: data)
    }

    public func activeReminders() -> [Reminder] {
        allReminders().filter { $0.isActive }
    }

    public func set(_ reminder: Reminder) {
        let data = (try? JSONEncoder().encode(reminder)) ?? Data()
        defaults.set(data, forKey: keyPrefix + reminder.noteID.uuidString)
    }

    public func clear(for noteID: UUID) {
        defaults.removeObject(forKey: keyPrefix + noteID.uuidString)
    }

    public func markFired(_ reminderID: UUID, at date: Date) {
        // Walk all reminders — cheap even for hundreds of notes and
        // avoids a second reminderID → noteID index.
        for r in allReminders() where r.id == reminderID {
            var updated = r
            updated.fired = true
            updated.firedAt = date
            set(updated)
            return
        }
    }

    /// Enumerate every reminder in the suite. Used by
    /// `activeReminders()` and `markFired`.
    private func allReminders() -> [Reminder] {
        let all = defaults.dictionaryRepresentation()
        return all.compactMap { (key, value) -> Reminder? in
            guard key.hasPrefix(keyPrefix),
                  let data = value as? Data else { return nil }
            return try? JSONDecoder().decode(Reminder.self, from: data)
        }
    }

    /// Test-only helper: wipe every reminder. Not on the protocol;
    /// production code has no reason to clear all at once.
    func wipeAllForTesting() {
        for (key, _) in defaults.dictionaryRepresentation() where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
