import AppKit
import NotesKit

/// Mac-only helpers for showing a note in lists and menus: a small color
/// swatch image. Title / snippet / relative-time / attachment-reference
/// helpers live in `Shared/NotePreviewText.swift` and are forwarded here
/// so existing Mac call sites stay unchanged. iOS uses NotePreviewText
/// directly.
enum NotePreview {
    static func title(for note: Note) -> String { NotePreviewText.title(for: note) }
    static func snippet(for note: Note) -> String { NotePreviewText.snippet(for: note) }
    static func relativeTime(for date: Date, now: Date = Date()) -> String {
        NotePreviewText.relativeTime(for: date, now: now)
    }
    static func hasAttachmentReference(_ note: Note) -> Bool {
        NotePreviewText.hasAttachmentReference(note)
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
