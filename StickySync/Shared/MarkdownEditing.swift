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

public enum NewlineAction: Equatable {
    /// The current list line has nothing but the prefix; pressing Enter
    /// cancels the prefix (so the user is out of the list) rather than
    /// continuing it. Caller should delete `removeRange` and consume Enter.
    case cancelPrefix(removeRange: NSRange)
    /// The current line is a non-empty list item; on Enter, insert this
    /// string at the insertion point and consume the keystroke. The string
    /// is `\n` plus the continuation prefix.
    case insertString(String)
}

public enum MarkdownEditing {

    /// Decide what should happen when the user presses Enter at `point`. If
    /// nil, the caller should let the system handle Enter normally.
    ///
    /// Behavior:
    ///   * `- item`              + Enter → insert `\n- ` on next line.
    ///   * `- `                  + Enter → cancel the prefix (exit list).
    ///   * `- [ ] item`          + Enter → insert `\n- [ ] `.
    ///   * `- [ ] `              + Enter → cancel the prefix.
    ///   * `- [x] item`          + Enter → insert `\n- [ ] ` (continuation
    ///                                      defaults to unchecked).
    ///   * `- [x] `              + Enter → cancel the prefix.
    public static func newlineAction(in storage: NSMutableAttributedString,
                                     at point: Int) -> NewlineAction? {
        let ns = storage.string as NSString
        guard point >= 0, point <= ns.length else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: point, length: 0))
        // Strip a trailing \n if present so prefix-detection sees the actual
        // line content.
        var contentLen = lineRange.length
        if contentLen > 0,
           ns.character(at: lineRange.location + contentLen - 1) == 0x0A {
            contentLen -= 1
        }
        let lineContent = ns.substring(with: NSRange(location: lineRange.location, length: contentLen)) as NSString
        guard let prefix = listPrefix(of: lineContent) else { return nil }

        if prefix.length == lineContent.length {
            // Line is the prefix and nothing else — user wants out.
            return .cancelPrefix(removeRange: NSRange(location: lineRange.location, length: prefix.length))
        }
        return .insertString("\n" + continuationPrefix(for: prefix as String))
    }

    /// Returns the prefix substring if `line` is a list item, else nil.
    private static func listPrefix(of line: NSString) -> NSString? {
        guard line.length >= 2 else { return nil }
        let first = line.character(at: 0)
        guard first == 0x2D || first == 0x2A else { return nil }
        guard line.character(at: 1) == 0x20 else { return nil }
        if line.length >= 6,
           line.character(at: 2) == 0x5B,
           (line.character(at: 3) == 0x20 || line.character(at: 3) == 0x78 || line.character(at: 3) == 0x58),
           line.character(at: 4) == 0x5D,
           line.character(at: 5) == 0x20 {
            return line.substring(with: NSRange(location: 0, length: 6)) as NSString
        }
        return line.substring(with: NSRange(location: 0, length: 2)) as NSString
    }

    /// Continuation prefix: a checked item rolls forward as unchecked, so
    /// you don't accidentally mark a brand-new line as already-done.
    private static func continuationPrefix(for prefix: String) -> String {
        switch prefix {
        case "- [x] ", "- [X] ": return "- [ ] "
        case "* [x] ", "* [X] ": return "* [ ] "
        default: return prefix
        }
    }


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
