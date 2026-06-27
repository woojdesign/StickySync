// MarkdownNSTextView.swift
//
// Thin NSTextView subclass that maps the standard formatting shortcuts —
// ⌘B, ⌘I, ⌘⇧X, ⌘K — into Markdown syntax edits on the text storage. The
// rendered styling falls out automatically once the storage's
// processEditing runs.
//
// `bold(_:)` / `italic(_:)` on NSResponder are informal-protocol selectors,
// not real methods on NSTextView, so we don't override them — instead we
// intercept all four shortcuts at the key-equivalent layer where we can
// handle them without depending on a Format menu being wired into the app.

import AppKit
import NotesKit

final class MarkdownNSTextView: NSTextView {

    /// Set by `NoteWindowController` so paste knows which note to upload
    /// image bytes into. `onPasted` fires after a successful image paste so
    /// the controller can sync the new Markdown content back to NotesKit.
    struct AttachmentContext {
        let noteID: UUID?
        weak var noteStore: AnyObject?
        let onPasted: () -> Void
    }
    var attachmentContext: AttachmentContext?

    /// Accept the very first mouse-down on an inactive window — without
    /// this, clicking a note window from another app activates StickySync
    /// but the click is swallowed by the activation cycle, leaving the
    /// caret invisible until the user `⌘-Tab`s out and back in.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Click on a `[ ]` / `[x]` slot toggles the checkbox without placing
    /// the cursor inside it. Clicks outside the slot fall through to the
    /// default selection behavior.
    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: local)
        if let storage = textStorage,
           let hit = MarkdownEditing.checkboxHit(in: storage, at: index) {
            MarkdownEditing.applyCheckboxToggle(in: storage, hit: hit)
            // Park the cursor just after the toggled slot so the user can
            // keep typing on the same line if they want, without it landing
            // inside the brackets.
            setSelectedRange(NSRange(location: hit.toggleRange.upperBound + 1, length: 0))
            return
        }
        super.mouseDown(with: event)
    }

    /// Auto-continue list items when the user hits Enter: `- item ⏎` lands
    /// the cursor on the next line already prefixed with `- `. An Enter on
    /// an empty list line cancels the prefix (so you can step out of the
    /// list without manual deletion).
    override func insertNewline(_ sender: Any?) {
        if let storage = textStorage,
           let action = MarkdownEditing.newlineAction(in: storage, at: selectedRange().location) {
            switch action {
            case .cancelPrefix(let removeRange):
                storage.replaceCharacters(in: removeRange, with: "")
                setSelectedRange(NSRange(location: removeRange.location, length: 0))
                return
            case .insertString(let s):
                let r = selectedRange()
                storage.replaceCharacters(in: r, with: s)
                setSelectedRange(NSRange(location: r.location + (s as NSString).length, length: 0))
                return
            }
        }
        super.insertNewline(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let storage = textStorage else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == [.command] {
            switch chars {
            case "b":
                setSelectedRange(MarkdownEditing.toggleBold(in: storage, range: selectedRange()))
                return true
            case "i":
                setSelectedRange(MarkdownEditing.toggleItalic(in: storage, range: selectedRange()))
                return true
            case "k":
                setSelectedRange(MarkdownEditing.insertLink(in: storage, range: selectedRange()))
                return true
            default:
                break
            }
        }
        if flags == [.command, .shift], chars == "x" {
            setSelectedRange(MarkdownEditing.toggleStrikethrough(in: storage, range: selectedRange()))
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Paste

    /// Tell NSTextView's Edit-menu validator that we know how to consume
    /// image pasteboard types — without this, the system grays out Paste
    /// when the clipboard holds *only* an image (e.g. a `⌘⇧4` screenshot),
    /// and `paste(_:)` never even gets called.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            .tiff,
            .png
        ]
    }

    /// Drag-drop equivalent of `readablePasteboardTypes` — let the user drop
    /// an image file directly onto the note's text area.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            .tiff,
            .png,
            .fileURL
        ]
    }

    /// Paste intercept. When the pasteboard carries an image, upload through
    /// NotesKit and insert a Markdown reference. Anything else falls through
    /// to the default behavior (text, RTF, etc.).
    override func paste(_ sender: Any?) {
        if let context = attachmentContext,
           let noteID = context.noteID,
           let store = context.noteStore as? NoteStore,
           let payload = bestImagePayload(from: NSPasteboard.general),
           let image = NSImage(data: payload.data),
           let attachment = store.addImageAttachment(
                for: noteID,
                imageData: payload.data,
                mimeType: payload.mimeType,
                originalFilename: nil,
                altText: nil
           ),
           let storage = textStorage as? MarkdownTextStorage {
            let insertAt = selectedRange().location
            storage.insertAttachment(id: attachment.id,
                                     altText: "",
                                     image: image,
                                     at: insertAt)
            setSelectedRange(NSRange(location: insertAt + 1, length: 0))
            context.onPasted()
            return
        }
        super.paste(sender)
    }

    /// Read the highest-fidelity image off the pasteboard. PNG / HEIC first
    /// (lossless / native), then JPEG, then TIFF/generic so we don't drop a
    /// screenshot from older sources.
    private func bestImagePayload(from pb: NSPasteboard) -> (data: Data, mimeType: String)? {
        if let png = pb.data(forType: NSPasteboard.PasteboardType("public.png"))
            ?? pb.data(forType: .png) {
            return (png, "image/png")
        }
        if let heic = pb.data(forType: NSPasteboard.PasteboardType("public.heic")) {
            return (heic, "image/heic")
        }
        if let jpeg = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            return (jpeg, "image/jpeg")
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "image/png")
        }
        return nil
    }
}
