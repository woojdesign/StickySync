// RemindTrigger.swift
//
// 0.12.1: pure detector for the /remind slash-command. Given the
// full note text and the cursor position, returns whether the
// current line is a /remind trigger AND the range to strip on
// confirm.
//
// Design decisions from the UX research pass (see the deep-dive
// writeup):
//   - Trigger at LINE START (or after whitespace on the line).
//     Prevents accidental fires mid-word or mid-URL.
//   - Case-insensitive match: "/Remind" and "/REMIND" both fire.
//   - Matches "/remind" followed by end-of-line, whitespace, or
//     more text. "/reminder" or "/remindME" (no separator) does
//     NOT fire — we want a clean word boundary.
//   - The strip range covers the entire line (`/remind …\n`), so
//     nothing about the trigger stays in the note after confirm.

import Foundation

enum RemindTrigger {
    /// Result of scanning text at a cursor position.
    struct Match: Equatable {
        /// The NSRange of the whole line that would be stripped on
        /// confirm. Includes the trailing newline if there is one.
        let lineRangeToStrip: NSRange
        /// The raw content of the line after `/remind` (whatever the
        /// user typed as free text — will be fed to the NL parser in
        /// 0.12.2). Empty string if the user only typed `/remind`.
        let freeText: String
    }

    /// Returns a Match if the line containing `cursor` starts with
    /// `/remind` as a standalone token. Returns nil otherwise.
    static func detect(in text: String, at cursor: Int) -> Match? {
        let ns = text as NSString
        guard cursor >= 0, cursor <= ns.length else { return nil }

        // Find the line containing the cursor. `lineRange(for:)`
        // returns the range including the trailing newline (if any).
        let cursorRange = NSRange(location: min(cursor, ns.length),
                                  length: 0)
        let lineRange = ns.lineRange(for: cursorRange)
        let line = ns.substring(with: lineRange)

        // Strip a trailing \n for the trigger check but remember
        // the full range for the strip.
        let trimmed = line.hasSuffix("\n") ? String(line.dropLast()) : line

        // Trigger: line begins with optional leading whitespace,
        // then "/remind" (case-insensitive), then either end-of-
        // line OR at least one whitespace character before any
        // free text.
        let pattern = #"^\s*/remind(?:\s+(.*))?$"#
        guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]) else { return nil }
        let searchRange = NSRange(location: 0, length: trimmed.utf16.count)
        guard let m = regex.firstMatch(in: trimmed, options: [],
                                       range: searchRange) else {
            return nil
        }

        let free: String
        if m.numberOfRanges >= 2 {
            let g = m.range(at: 1)
            if g.location != NSNotFound {
                free = (trimmed as NSString).substring(with: g)
            } else {
                free = ""
            }
        } else {
            free = ""
        }

        return Match(lineRangeToStrip: lineRange, freeText: free)
    }
}
