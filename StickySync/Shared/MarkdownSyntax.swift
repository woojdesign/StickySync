// MarkdownSyntax.swift
//
// A small Markdown-syntax scanner for sticky notes. Foundation-only — no UI
// framework deps — so the same code runs on Mac and iOS. It returns a flat
// sequence of "runs": each is an NSRange in the source plus a description of
// the style at that range (bold/italic/strike/heading/list/link, plus an
// `isMarker` flag on the syntax characters themselves so the text storage can
// fade them).
//
// What's supported (the StickySync subset — keep this small on purpose):
//   **bold**, __bold__
//   *italic*, _italic_
//   ~~strikethrough~~
//   # heading, ## heading, ### heading      (one per line, at line start)
//   - bullet item, * bullet item            (at line start)
//   - [ ] unchecked, - [x] checked          (at line start)
//   [text](url)
//
// Deliberately NOT supported: inline code, code blocks, tables, images,
// blockquotes, footnotes, horizontal rules, nested lists with indentation.
// A sticky note is not a document — see CLAUDE.md scope rules.

import Foundation

public enum ListMarker: Equatable {
    case bullet
    case checkboxUnchecked
    case checkboxChecked
}

public struct MarkdownStyle: Equatable {
    public var bold: Bool = false
    public var italic: Bool = false
    public var strikethrough: Bool = false
    /// Heading level 1...3; nil means body.
    public var heading: Int? = nil
    /// True for the syntax characters themselves (`*`, `_`, `~`, `#`, `[`, `]`,
    /// `(`, `)`, the leading `-` / `*` of a list, and the `[ ]` / `[x]` of a
    /// checkbox). The text storage uses this to fade them.
    public var isMarker: Bool = false
    /// Set on the visible text of `[text](url)` runs; the URL itself is in
    /// `linkURL`. The `(url)` part is marked `isMarker` and styled subtly.
    public var linkURL: String? = nil
    /// Present on the marker prefix of a list line; lets the text storage
    /// draw a custom bullet glyph or a checkbox in place of `-` / `- [ ]`.
    public var listMarker: ListMarker? = nil

    public init() {}
}

public struct MarkdownRun: Equatable {
    public let range: NSRange
    public let style: MarkdownStyle
}

public enum MarkdownSyntax {

    /// Parse `text` and return a flat, non-overlapping sequence of runs that
    /// covers the entire string. Empty input returns an empty array.
    public static func parse(_ text: String) -> [MarkdownRun] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }

        var runs: [MarkdownRun] = []
        var lineStart = 0
        while lineStart < ns.length {
            let lineEnd = ns.range(of: "\n", range: NSRange(location: lineStart, length: ns.length - lineStart)).location
            let lineLen: Int
            let contentLen: Int
            if lineEnd == NSNotFound {
                lineLen = ns.length - lineStart
                contentLen = lineLen
            } else {
                lineLen = lineEnd - lineStart + 1  // include the \n
                contentLen = lineEnd - lineStart   // excludes the \n
            }
            let lineRange = NSRange(location: lineStart, length: lineLen)
            let contentRange = NSRange(location: lineStart, length: contentLen)
            parseLine(in: ns, lineRange: lineRange, contentRange: contentRange, into: &runs)
            lineStart += lineLen
        }
        return mergeAdjacent(runs)
    }

    // MARK: - Line-level parsing (block prefixes + inline)

    private static func parseLine(in ns: NSString,
                                  lineRange: NSRange,
                                  contentRange: NSRange,
                                  into runs: inout [MarkdownRun]) {
        let line = ns.substring(with: contentRange) as NSString

        // Heading: leading 1-3 `#` then a space then content.
        if let (level, prefixLen) = detectHeading(in: line) {
            let prefixRange = NSRange(location: contentRange.location, length: prefixLen)
            var prefixStyle = MarkdownStyle()
            prefixStyle.isMarker = true
            prefixStyle.heading = level
            runs.append(MarkdownRun(range: prefixRange, style: prefixStyle))

            let remainder = NSRange(location: contentRange.location + prefixLen,
                                    length: contentRange.length - prefixLen)
            var contentStyle = MarkdownStyle()
            contentStyle.heading = level
            parseInline(in: ns, range: remainder, baseStyle: contentStyle, into: &runs)
            appendTrailingNewline(lineRange: lineRange, contentRange: contentRange, into: &runs)
            return
        }

        // List: -[space], *[space], with optional `[ ]` or `[x]` checkbox.
        if let parsed = detectList(in: line) {
            let prefixRange = NSRange(location: contentRange.location, length: parsed.prefixLen)
            var prefixStyle = MarkdownStyle()
            prefixStyle.isMarker = true
            prefixStyle.listMarker = parsed.kind
            runs.append(MarkdownRun(range: prefixRange, style: prefixStyle))

            let remainder = NSRange(location: contentRange.location + parsed.prefixLen,
                                    length: contentRange.length - parsed.prefixLen)
            var contentStyle = MarkdownStyle()
            if parsed.kind == .checkboxChecked {
                contentStyle.strikethrough = true  // checked items read as struck-through
            }
            parseInline(in: ns, range: remainder, baseStyle: contentStyle, into: &runs)
            appendTrailingNewline(lineRange: lineRange, contentRange: contentRange, into: &runs)
            return
        }

        // Plain body line — just inline.
        parseInline(in: ns, range: contentRange, baseStyle: MarkdownStyle(), into: &runs)
        appendTrailingNewline(lineRange: lineRange, contentRange: contentRange, into: &runs)
    }

    private static func appendTrailingNewline(lineRange: NSRange,
                                              contentRange: NSRange,
                                              into runs: inout [MarkdownRun]) {
        // The `\n` itself (if any) is a plain run so callers can iterate the
        // whole string from runs without gaps.
        if lineRange.length > contentRange.length {
            let nlRange = NSRange(location: contentRange.upperBound,
                                  length: lineRange.length - contentRange.length)
            runs.append(MarkdownRun(range: nlRange, style: MarkdownStyle()))
        }
    }

    // MARK: - Block prefix detectors

    /// Returns `(headingLevel, prefixLength)` if the line starts with `# `,
    /// `## `, or `### `. Counts the trailing space as part of the prefix.
    private static func detectHeading(in line: NSString) -> (Int, Int)? {
        var hashes = 0
        var i = 0
        while i < line.length && line.character(at: i) == 0x23 /* '#' */ {
            hashes += 1
            i += 1
        }
        guard hashes >= 1 && hashes <= 3 else { return nil }
        guard i < line.length && line.character(at: i) == 0x20 /* ' ' */ else { return nil }
        return (hashes, i + 1)
    }

    private struct ListPrefix {
        let prefixLen: Int
        let kind: ListMarker
    }

    /// Returns the list prefix info for lines that start with `- `, `* `, or
    /// `- [ ] `, `- [x] ` (and `*` variants).
    private static func detectList(in line: NSString) -> ListPrefix? {
        guard line.length >= 2 else { return nil }
        let first = line.character(at: 0)
        guard first == 0x2D /* - */ || first == 0x2A /* * */ else { return nil }
        guard line.character(at: 1) == 0x20 /* space */ else { return nil }

        // Probe for `[ ]` / `[x]` / `[X]` immediately after the space.
        if line.length >= 5,
           line.character(at: 2) == 0x5B /* [ */,
           (line.character(at: 3) == 0x20 || line.character(at: 3) == 0x78 || line.character(at: 3) == 0x58),
           line.character(at: 4) == 0x5D /* ] */ {
            // Need at least a space after `]`.
            if line.length >= 6 && line.character(at: 5) == 0x20 {
                let checked = (line.character(at: 3) == 0x78 || line.character(at: 3) == 0x58)
                return ListPrefix(prefixLen: 6, kind: checked ? .checkboxChecked : .checkboxUnchecked)
            }
        }
        return ListPrefix(prefixLen: 2, kind: .bullet)
    }

    // MARK: - Inline parsing (bold/italic/strike/link)

    private static func parseInline(in ns: NSString,
                                    range: NSRange,
                                    baseStyle: MarkdownStyle,
                                    into runs: inout [MarkdownRun]) {
        guard range.length > 0 else { return }
        let text = ns.substring(with: range) as NSString
        var cursor = 0  // index into `text`

        // We'll emit runs in `text`-relative coords, then shift to `ns` coords
        // before appending. Track current plain-run start.
        var plainStart: Int? = 0

        func flushPlain(upTo end: Int) {
            guard let start = plainStart, end > start else { return }
            let r = NSRange(location: range.location + start, length: end - start)
            runs.append(MarkdownRun(range: r, style: baseStyle))
            plainStart = nil
        }

        while cursor < text.length {
            // Try each inline pattern at the current cursor.
            if let m = matchBold(in: text, at: cursor) {
                flushPlain(upTo: cursor)
                emitWrapped(in: text, offset: range.location, span: m, marker: m.markerLen, style: { var s = baseStyle; s.bold = true; return s }(), into: &runs)
                cursor = m.end
                plainStart = cursor
                continue
            }
            if let m = matchStrike(in: text, at: cursor) {
                flushPlain(upTo: cursor)
                emitWrapped(in: text, offset: range.location, span: m, marker: m.markerLen, style: { var s = baseStyle; s.strikethrough = true; return s }(), into: &runs)
                cursor = m.end
                plainStart = cursor
                continue
            }
            if let m = matchItalic(in: text, at: cursor) {
                flushPlain(upTo: cursor)
                emitWrapped(in: text, offset: range.location, span: m, marker: m.markerLen, style: { var s = baseStyle; s.italic = true; return s }(), into: &runs)
                cursor = m.end
                plainStart = cursor
                continue
            }
            if let m = matchLink(in: text, at: cursor) {
                flushPlain(upTo: cursor)
                emitLink(in: text, offset: range.location, match: m, base: baseStyle, into: &runs)
                cursor = m.end
                plainStart = cursor
                continue
            }
            if plainStart == nil { plainStart = cursor }
            cursor += 1
        }
        flushPlain(upTo: text.length)
    }

    // MARK: - Inline matchers

    private struct WrappedMatch {
        let start: Int
        let end: Int         // exclusive
        let innerStart: Int  // first char of content (after opening marker)
        let innerEnd: Int    // exclusive end of content (before closing marker)
        let markerLen: Int
    }

    private struct LinkMatch {
        let start: Int       // `[`
        let textStart: Int   // first char after `[`
        let textEnd: Int     // `]`
        let urlStart: Int    // first char after `(`
        let urlEnd: Int      // `)`
        let end: Int         // one past `)`
    }

    /// `**...**` or `__...__`.
    private static func matchBold(in s: NSString, at i: Int) -> WrappedMatch? {
        guard i + 4 <= s.length else { return nil }
        let c0 = s.character(at: i)
        guard c0 == 0x2A /* * */ || c0 == 0x5F /* _ */ else { return nil }
        guard s.character(at: i + 1) == c0 else { return nil }
        // Find closing `c0c0`.
        var j = i + 2
        while j + 1 < s.length {
            if s.character(at: j) == c0 && s.character(at: j + 1) == c0 {
                // Disallow empty content.
                if j > i + 2 {
                    return WrappedMatch(start: i, end: j + 2, innerStart: i + 2, innerEnd: j, markerLen: 2)
                }
                return nil
            }
            j += 1
        }
        return nil
    }

    /// Single `*...*` or `_..._`. Must not be a bold marker (caller handles
    /// bold first, so this only sees the leftover case).
    private static func matchItalic(in s: NSString, at i: Int) -> WrappedMatch? {
        guard i + 2 <= s.length else { return nil }
        let c0 = s.character(at: i)
        guard c0 == 0x2A /* * */ || c0 == 0x5F /* _ */ else { return nil }
        // Don't open italic if the next char is the same (would be bold).
        if i + 1 < s.length && s.character(at: i + 1) == c0 { return nil }
        var j = i + 1
        while j < s.length {
            let cj = s.character(at: j)
            if cj == c0 {
                // Closing must not be immediately followed by another same
                // character (would be the inside of a bold token).
                if j > i + 1 && (j + 1 >= s.length || s.character(at: j + 1) != c0) {
                    return WrappedMatch(start: i, end: j + 1, innerStart: i + 1, innerEnd: j, markerLen: 1)
                }
            }
            if cj == 0x0A /* \n */ { return nil }  // don't span lines
            j += 1
        }
        return nil
    }

    /// `~~...~~`.
    private static func matchStrike(in s: NSString, at i: Int) -> WrappedMatch? {
        guard i + 4 <= s.length else { return nil }
        guard s.character(at: i) == 0x7E && s.character(at: i + 1) == 0x7E else { return nil }
        var j = i + 2
        while j + 1 < s.length {
            if s.character(at: j) == 0x7E && s.character(at: j + 1) == 0x7E {
                if j > i + 2 {
                    return WrappedMatch(start: i, end: j + 2, innerStart: i + 2, innerEnd: j, markerLen: 2)
                }
                return nil
            }
            if s.character(at: j) == 0x0A { return nil }
            j += 1
        }
        return nil
    }

    /// `[text](url)`.
    private static func matchLink(in s: NSString, at i: Int) -> LinkMatch? {
        guard s.character(at: i) == 0x5B /* [ */ else { return nil }
        var j = i + 1
        while j < s.length {
            let c = s.character(at: j)
            if c == 0x5D /* ] */ {
                guard j + 1 < s.length && s.character(at: j + 1) == 0x28 /* ( */ else { return nil }
                let urlStart = j + 2
                var k = urlStart
                while k < s.length {
                    let ck = s.character(at: k)
                    if ck == 0x29 /* ) */ {
                        if k > urlStart && j > i + 1 {
                            return LinkMatch(start: i, textStart: i + 1, textEnd: j, urlStart: urlStart, urlEnd: k, end: k + 1)
                        }
                        return nil
                    }
                    if ck == 0x0A { return nil }
                    k += 1
                }
                return nil
            }
            if c == 0x0A { return nil }
            j += 1
        }
        return nil
    }

    // MARK: - Emit helpers

    private static func emitWrapped(in text: NSString,
                                    offset: Int,
                                    span m: WrappedMatch,
                                    marker: Int,
                                    style content: MarkdownStyle,
                                    into runs: inout [MarkdownRun]) {
        var markerStyle = content
        markerStyle.isMarker = true
        runs.append(MarkdownRun(range: NSRange(location: offset + m.start, length: marker), style: markerStyle))
        runs.append(MarkdownRun(range: NSRange(location: offset + m.innerStart, length: m.innerEnd - m.innerStart), style: content))
        runs.append(MarkdownRun(range: NSRange(location: offset + m.innerEnd, length: marker), style: markerStyle))
    }

    private static func emitLink(in text: NSString,
                                 offset: Int,
                                 match m: LinkMatch,
                                 base: MarkdownStyle,
                                 into runs: inout [MarkdownRun]) {
        let url = text.substring(with: NSRange(location: m.urlStart, length: m.urlEnd - m.urlStart))
        var markerStyle = base
        markerStyle.isMarker = true
        var linkStyle = base
        linkStyle.linkURL = url

        // `[`
        runs.append(MarkdownRun(range: NSRange(location: offset + m.start, length: 1), style: markerStyle))
        // visible text
        runs.append(MarkdownRun(range: NSRange(location: offset + m.textStart, length: m.textEnd - m.textStart), style: linkStyle))
        // `]` + `(` + url + `)` — all markers, single run for the url block
        let tailLen = m.end - m.textEnd
        runs.append(MarkdownRun(range: NSRange(location: offset + m.textEnd, length: tailLen), style: markerStyle))
    }

    // MARK: - Cleanup

    /// Merge adjacent runs with equal styles so consumers see fewer runs.
    private static func mergeAdjacent(_ runs: [MarkdownRun]) -> [MarkdownRun] {
        guard runs.count > 1 else { return runs }
        var out: [MarkdownRun] = []
        out.reserveCapacity(runs.count)
        for r in runs {
            if let last = out.last,
               last.style == r.style,
               last.range.upperBound == r.range.location {
                let merged = NSRange(location: last.range.location, length: last.range.length + r.range.length)
                out.removeLast()
                out.append(MarkdownRun(range: merged, style: last.style))
            } else {
                out.append(r)
            }
        }
        return out
    }
}
