// SyncLogger.swift
//
// Structured os_log surface for the last-write-wins (LWW) decision points
// on both platforms. Lets us reconstruct a forensic timeline of what the
// sync code actually decided when a tester reports "I lost an edit" — or,
// just as usefully, *confirms* the gate fired correctly and dropped a
// stale-remote that would have wiped local work pre-0.7.11.
//
// Why: prior to 0.7.11 we were entirely inference-driven about whether
// our LWW gates worked. The dabi paste-image-loss bug existed for weeks
// before anyone could repro it because there was no record of what
// `refresh(from:)` decided when. This file closes that gap.
//
// Querying the trail (Mac):
//   log show --predicate 'subsystem == "wooj.sync.lww"' --last 1h
//
// Querying on iOS (with the device attached to Xcode):
//   Console.app → device → search "wooj.sync.lww"
//   or `sysdiagnose` and grep the resulting `system_logs.logarchive`.
//
// Privacy: all timestamps + decision strings are public (no PII).
// `noteID` is private by default so logs uploaded to support don't leak
// note identities. Decision codes are short string literals so the
// predicate filter and grep both work cleanly.

import Foundation
import OSLog

enum SyncLog {
    /// LWW decision-point logger. One category, four event types
    /// (decision names) so the predicate filter stays simple.
    static let gate = Logger(subsystem: "wooj.sync.lww", category: "gate")

    /// Voice-capture pipeline logger — every step of the WhisperKit
    /// polish path so we can tell "Whisper agreed with SFSpeech" from
    /// "Whisper silently errored" from "model still downloading." Pre-
    /// 0.8.3 these all looked identical to the user (no text change,
    /// no error). Query: `log show --predicate 'subsystem == "wooj.voice"' --last 10m`
    static let voice = Logger(subsystem: "wooj.voice", category: "polish")

    /// Format a Note ID for the log — short suffix is enough to correlate
    /// across events without leaking the full UUID into a support bundle.
    static func short(_ id: UUID) -> String {
        let s = id.uuidString
        return String(s.suffix(8))
    }

    /// Format a Date as an ISO-ish epoch-millis string so timelines
    /// reconstruct cleanly without timezone surprises. (`os_log`'s
    /// `%@.description` for Date is locale-sensitive.)
    static func ts(_ date: Date) -> String {
        let ms = Int64(date.timeIntervalSince1970 * 1000)
        return String(ms)
    }
}
