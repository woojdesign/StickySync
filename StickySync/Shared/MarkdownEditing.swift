// MarkdownEditing.swift
//
// Selection-aware wrap / unwrap helpers for the standard editor shortcuts
// (⌘B, ⌘I, ⌘⇧X, ⌘K). All edits happen against `NSMutableAttributedString`
// because both NSTextView's `textStorage` and a UITextView wrapper's
// `textStorage` are concrete NSMutableAttributedStrings under the hood — and
// our `MarkdownTextStorage` is the substrate, so the platform editors get
// re-styling for free after the edit.
//
// Behavior is symmetric: invoking the same shortcut on an already-wrapped
// selection unwraps it. Empty selection inserts the marker pair and parks
// the cursor in the middle (so ⌘B on nothing types `**|**`).

import Foundation

public enum MarkdownEditing {

    /// Toggle bold (`**...**`) on the given selection.
    public static func toggleBold(in storage: NSMutableAttributedString,
                                  range: NSRange) -> NSRange {
        wrapOrUnwrap(in: storage, range: range, with: "**")
    }

    /// Toggle italic (`_..._`). We pick `_` over `*` to avoid the visual
    /// confusion of single vs double `*` mid-edit.
    public static func toggleItalic(in storage: NSMutableAttributedString,
                                    range: NSRange) -> NSRange {
        wrapOrUnwrap(in: storage, range: range, with: "_")
    }

    /// Toggle strikethrough (`~~...~~`). Especially useful on checkbox lists
    /// where the checked state already implies strike — the explicit version
    /// is for one-off "we tried this" markings.
    public static func toggleStrikethrough(in storage: NSMutableAttributedString,
                                           range: NSRange) -> NSRange {
        wrapOrUnwrap(in: storage, range: range, with: "~~")
    }

    /// Insert a link template at the selection. If the selection has text,
    /// it becomes the link's visible text; the returned range covers the
    /// placeholder `url` for the editor to select so the user can paste.
    public static func insertLink(in storage: NSMutableAttributedString,
                                  range: NSRange) -> NSRange {
        let ns = storage.string as NSString
        let visible = range.length > 0 ? ns.substring(with: range) : "text"
        let replacement = "[\(visible)](url)"
        storage.replaceCharacters(in: range, with: replacement)
        // Position so the editor can select `url` for immediate replacement.
        let urlStart = range.location + ("[\(visible)](" as NSString).length
        return NSRange(location: urlStart, length: 3)
    }

    /// Toggle a checkbox prefix on the line containing `range.location`. If
    /// the line is plain, prefix it with `- [ ] `. If it's `- [ ] `, flip to
    /// `- [x] `. If it's `- [x] `, strip the prefix entirely. Returns the
    /// adjusted selection.
    public static func toggleCheckbox(in storage: NSMutableAttributedString,
                                      range: NSRange) -> NSRange {
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
        let line = ns.substring(with: lineRange) as NSString

        let unchecked = "- [ ] "
        let checked = "- [x] "

        if line.hasPrefix(unchecked) {
            // unchecked → checked (flip the `[ ]` to `[x]`)
            let xRange = NSRange(location: lineRange.location + 3, length: 1)
            storage.replaceCharacters(in: xRange, with: "x")
            return range
        }
        if line.hasPrefix(checked) {
            // checked → remove the whole prefix.
            let prefixRange = NSRange(location: lineRange.location, length: (checked as NSString).length)
            storage.replaceCharacters(in: prefixRange, with: "")
            return NSRange(location: range.location - (checked as NSString).length,
                           length: range.length)
        }
        // plain → add unchecked prefix at the start of the line.
        let insertAt = NSRange(location: lineRange.location, length: 0)
        storage.replaceCharacters(in: insertAt, with: unchecked)
        return NSRange(location: range.location + (unchecked as NSString).length,
                       length: range.length)
    }

    // MARK: - Internals

    /// Wrap the selection with `marker` on each side, OR unwrap if the
    /// surrounding characters already match. Returns the post-edit selection
    /// that callers should restore on the text view.
    private static func wrapOrUnwrap(in storage: NSMutableAttributedString,
                                     range: NSRange,
                                     with marker: String) -> NSRange {
        let ns = storage.string as NSString
        let m = marker as NSString
        let mLen = m.length

        // Empty selection: insert pair, cursor in the middle.
        if range.length == 0 {
            storage.replaceCharacters(in: range, with: marker + marker)
            return NSRange(location: range.location + mLen, length: 0)
        }

        // Is the selection already wrapped?
        if range.location >= mLen && range.upperBound + mLen <= ns.length {
            let beforeRange = NSRange(location: range.location - mLen, length: mLen)
            let afterRange = NSRange(location: range.upperBound, length: mLen)
            if ns.substring(with: beforeRange) == marker,
               ns.substring(with: afterRange) == marker {
                // Unwrap. Order: trailing first so the leading delete doesn't
                // shift its range.
                storage.replaceCharacters(in: afterRange, with: "")
                storage.replaceCharacters(in: beforeRange, with: "")
                return NSRange(location: range.location - mLen, length: range.length)
            }
        }

        // Otherwise wrap.
        let selected = ns.substring(with: range)
        storage.replaceCharacters(in: range, with: marker + selected + marker)
        return NSRange(location: range.location + mLen, length: range.length)
    }
}
