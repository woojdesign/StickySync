// NotePreviewText.swift
//
// Platform-agnostic helpers for rendering a note in lists, menus,
// and previews: title, snippet, relative time, attachment-reference
// detection. AppKit-specific bits (the swatch NSImage builder) stay
// in StickySync/StickySync/NotePreview.swift; iOS does its own
// SwiftUI swatch inline.
//
// Moved out of the Mac-only NotePreview.swift in 0.7.19 when the iOS
// list-view rows wanted the same title/snippet/time semantics as the
// Mac all-notes list. One helper, two consumers — no drift.

import Foundation
import NotesKit

enum NotePreviewText {
    /// First non-empty line, with markdown heading markers (`# `, `## `,
    /// …) stripped and truncated to 60 chars. Falls back to "New note"
    /// for empty notes.
    static func title(for note: Note) -> String {
        let lines = note.content.components(separatedBy: .newlines)
        let firstNonEmpty = lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let raw = (firstNonEmpty ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = stripHeadingMarker(raw)
        let text = stripped.isEmpty ? "New note" : stripped
        return text.count > 60 ? String(text.prefix(60)) + "…" : text
    }

    /// Body snippet: the next non-empty line after the title, with
    /// (1) `![alt](attachment://UUID)` collapsed to alt text and
    /// (2) heading markers stripped. Empty for notes that are just a
    /// title.
    static func snippet(for note: Note) -> String {
        let lines = note.content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return "" }
        let secondLine = lines[1]
        let withoutImages = secondLine.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(attachment://[^\)]+\)"#,
            with: "$1",
            options: .regularExpression)
        let stripped = stripHeadingMarker(
            withoutImages.trimmingCharacters(in: .whitespacesAndNewlines))
        return stripped.count > 80 ? String(stripped.prefix(80)) + "…" : stripped
    }

    /// Relative time for the row's right edge. "just now" / "12m ago"
    /// within the hour; "3:42 PM" today; "yesterday"; "Wed" within the
    /// week; "Mar 14" beyond.
    static func relativeTime(for date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "yesterday" }
        if elapsed < 60 * 60 * 24 * 7 {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// True if the note's body contains at least one `attachment://UUID`
    /// reference (the canonical inline-image form).
    static func hasAttachmentReference(_ note: Note) -> Bool {
        note.content.range(of: "attachment://", options: .caseInsensitive) != nil
    }

    /// Strip a leading CommonMark heading marker (`#`, `##`, … `######`)
    /// but only when followed by a space, so `#hashtag-style` text is
    /// preserved as-is.
    private static func stripHeadingMarker(_ s: String) -> String {
        guard let firstNonHash = s.firstIndex(where: { $0 != "#" }) else { return s }
        let hashCount = s.distance(from: s.startIndex, to: firstNonHash)
        guard hashCount > 0, hashCount <= 6,
              firstNonHash < s.endIndex, s[firstNonHash] == " " else {
            return s
        }
        return String(s[s.index(after: firstNonHash)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
