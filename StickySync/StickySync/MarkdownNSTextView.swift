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
}
