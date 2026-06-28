import AppKit
import NotesKit

/// Shared helpers for showing a note in lists and menus: a one-line title and
/// a small color swatch image.
enum NotePreview {
    /// First non-empty line, with markdown stripped from heading prefixes
    /// (`#`, `##`, etc.). Falls back to "New note" for empty notes.
    /// Truncated to 60 chars (the all-notes list has more horizontal
    /// room than the status-menu items).
    static func title(for note: Note) -> String {
        let lines = note.content.components(separatedBy: .newlines)
        let firstNonEmpty = lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let raw = (firstNonEmpty ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = stripHeadingMarker(raw)
        let text = stripped.isEmpty ? "New note" : stripped
        return text.count > 60 ? String(text.prefix(60)) + "…" : text
    }

    /// Body snippet: the next non-empty line after the title, with the
    /// `![alt](attachment://UUID)` references collapsed to their alt text
    /// (or hidden if no alt) so the row stays scannable. Empty string if
    /// the note has no body beyond its title.
    static func snippet(for note: Note) -> String {
        let lines = note.content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return "" }
        let secondLine = lines[1]
        // Strip image markdown so a body that starts with an inline image
        // doesn't render as `![](attachment://UUID)` in the list.
        let withoutImages = secondLine.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(attachment://[^\)]+\)"#,
            with: "$1",
            options: .regularExpression)
        let cleaned = withoutImages.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 80 ? String(cleaned.prefix(80)) + "…" : cleaned
    }

    /// Relative time for the all-notes row's right edge. Today within
    /// the hour → "12m ago", within today → "3:42 PM", within the last
    /// week → "Mon", older → "Mar 14". Cheap to call per row.
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

    /// True if the note's body contains at least one
    /// `attachment://UUID` reference (the canonical inline-image form).
    /// Cheap substring check; the cell uses it to decide whether to show
    /// the paperclip indicator.
    static func hasAttachmentReference(_ note: Note) -> Bool {
        note.content.range(of: "attachment://", options: .caseInsensitive) != nil
    }

    /// Strip the leading `#`, `##`, `###` (etc.) + a space — only if the
    /// hash is followed by a space (so `#hashtag-style-text` is preserved
    /// as-is). Matches CommonMark heading rules.
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

    static func swatch(for token: String, size: CGFloat = 13) -> NSImage {
        let fill = Appearance.background(for: token)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3, yRadius: 3)
            fill.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
