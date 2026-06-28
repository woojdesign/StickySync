// SyncReport.swift
//
// Tier 1 verification surface: a one-tap "Report a Sync Issue…" report
// the user can send via Mail / Messages / AirDrop. Bundles app version,
// current sync state, and the last 30 minutes of `wooj.sync.lww` gate
// events into a single text file the user attaches without thinking
// about it.
//
// Tier 0 was the structured os_log we shipped 0.7.13 — the data exists.
// Tier 1 (this file) is the *user-facing* shape that lets a non-
// technical tester give us the data without knowing how `log show`
// works. The text thread that triggered this — "🙁 not synced. Help."
// → Sean having to play 20 questions over SMS — is exactly the
// conversation this replaces.
//
// What the report does NOT contain:
//   - Note content
//   - Note titles
//   - Full UUIDs (we already shortened to 8-char suffix in os_log)
//   - iCloud account / email
//   - Any identifier we don't already log
//
// The user always sees the payload before sending (via Preview), so
// the "send" tap is informed consent, not a silent exfiltration.

import Foundation
import OSLog

struct SyncReport {
    let appVersion: String
    let osVersion: String
    let device: String
    let generatedAt: Date
    /// SyncMonitor's current state as a printable string (e.g. "harmony",
    /// "syncing", "error(.quota)"). Kept platform-agnostic by passing in
    /// the string at build time — `SyncMonitor.State` is Mac-specific in
    /// some respects, and we don't want a cross-platform protocol just
    /// for this one field.
    let syncState: String
    /// Pre-formatted lines from the `wooj.sync.lww` subsystem, last
    /// `Self.lookbackMinutes` minutes. Empty if OSLogStore is unavailable
    /// (rare — sandbox restrictions only).
    let lwwEvents: [String]
    /// Tester-provided context: "what I was doing, what I expected."
    let userText: String

    static let lookbackMinutes: Int = 30

    /// Render the full report as the plaintext file body. Format is
    /// stable enough that we could parse 50 of these mechanically if we
    /// ever need to (don't yet — Tier 1 is for human-eyeball use).
    func formatted() -> String {
        let lwwBlock: String
        if lwwEvents.isEmpty {
            lwwBlock = "  (no LWW gate events in the last \(Self.lookbackMinutes) minutes)"
        } else {
            lwwBlock = lwwEvents.map { "  \($0)" }.joined(separator: "\n")
        }
        return """
        StickySync Sync Issue Report
        ============================
        Generated:  \(generatedAt.iso8601)
        App:        \(appVersion)
        OS:         \(osVersion)
        Device:     \(device)
        Sync state: \(syncState)

        What I was doing:
        \(userText.isEmpty ? "  (no description provided)" : userText.indented(by: "  "))

        LWW gate events (last \(Self.lookbackMinutes) min):
        \(lwwBlock)
        """
    }
}

enum SyncReportBuilder {
    /// Query OSLogStore for `wooj.sync.lww` entries from the last
    /// `SyncReport.lookbackMinutes` and return them as printable lines.
    /// `OSLogStore.local()` is `throws` on iOS and the sandbox can
    /// reject it under some entitlements; we swallow errors and return
    /// empty rather than fail the whole report.
    static func recentLWWEvents(now: Date = Date()) -> [String] {
        do {
            let store: OSLogStore
            #if os(macOS)
            store = try OSLogStore.local()
            #else
            store = try OSLogStore(scope: .currentProcessIdentifier)
            #endif
            let start = now.addingTimeInterval(-Double(SyncReport.lookbackMinutes * 60))
            let position = store.position(date: start)
            let predicate = NSPredicate(format: "subsystem == %@", "wooj.sync.lww")
            let entries = try store.getEntries(at: position, matching: predicate)
            return entries.compactMap { entry in
                guard let log = entry as? OSLogEntryLog else { return nil }
                let ts = log.date.iso8601
                return "\(ts)  \(log.composedMessage)"
            }
        } catch {
            return []
        }
    }
}

private extension String {
    /// Indent every line by the given prefix. Used for the user-text
    /// section so the report's overall shape stays scannable.
    func indented(by prefix: String) -> String {
        self.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }
}

private extension Date {
    /// ISO-8601 with timezone — stable across locales, sortable, the
    /// only Date string format we should ever embed in a report.
    var iso8601: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: self)
    }
}
