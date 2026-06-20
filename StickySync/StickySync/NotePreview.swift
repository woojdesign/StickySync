import AppKit
import NotesKit

/// Shared helpers for showing a note in lists and menus: a one-line title and
/// a small color swatch image.
enum NotePreview {
    static func title(for note: Note) -> String {
        let firstLine = note.content.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? "New note" : trimmed
        return text.count > 42 ? String(text.prefix(42)) + "…" : text
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
