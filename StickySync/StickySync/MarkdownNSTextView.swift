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

final class MarkdownNSTextView: NSTextView {

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
}
