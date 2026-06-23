// MarkdownTextStorage.swift
//
// An NSTextStorage subclass that re-styles its contents in place based on
// `MarkdownSyntax`. The underlying string stays plain Markdown — exactly what
// goes on disk and on the CloudKit wire — but the displayed glyph stream
// shows bold / italic / strikethrough / headings / list markers as styled
// text. Markup characters themselves are dimmed via `markerColor` so they're
// visible (you can edit them) but visually quiet.
//
// Used by both the Mac NSTextView in NoteContentView and the iOS UITextView
// wrapper in MarkdownTextView. One implementation, two platforms.
//
// The cursor-aware "hide the markers when not in this span" behavior is
// deliberately deferred to 0.4.1. v1 keeps markers always visible but dim;
// that's already a big improvement over plain text, and lets us ship.

import Foundation

#if canImport(AppKit)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
#endif

public final class MarkdownTextStorage: NSTextStorage {

    // The plain-Markdown backing store. `string` returns its string; all edits
    // route through `replaceCharacters(in:with:)` which mutates this.
    private let backing = NSMutableAttributedString()

    /// Body font for unstyled text. Bold/italic variants are derived from this
    /// via the font descriptor. Setting it triggers a full restyle.
    public var baseFont: PlatformFont {
        didSet { restyleAll() }
    }

    /// Color for the body text.
    public var textColor: PlatformColor {
        didSet { restyleAll() }
    }

    /// Color for syntax markers (`*`, `_`, `~`, `#`, list prefixes, `[](url)`
    /// parens). Should be a muted variant of `textColor` — somewhere around
    /// 35-45% opacity reads right against a sticky background.
    public var markerColor: PlatformColor {
        didSet { restyleAll() }
    }

    /// Paragraph range containing the current cursor / selection. Hideable
    /// inline markers OUTSIDE this range get faded to a much-dimmer color
    /// (~6% alpha) at draw time; INSIDE markers stay at the normal
    /// `markerColor`. `nil` means "no active selection yet" — all markers
    /// render at their normal `markerColor`.
    ///
    /// Updated by the host's selection observer (`textViewDidChangeSelection`
    /// on both platforms). Selection-driven, not edit-driven — no edit
    /// cycle, no cursor jump.
    private var activeLineRange: NSRange?

    public init(baseFont: PlatformFont, textColor: PlatformColor, markerColor: PlatformColor) {
        self.baseFont = baseFont
        self.textColor = textColor
        self.markerColor = markerColor
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    #if canImport(AppKit)
    public required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        fatalError("init(pasteboardPropertyList:ofType:) is not supported")
    }
    #endif

    #if canImport(UIKit)
    @available(iOS 15.0, *)
    required init(itemProviderData data: Data, typeIdentifier: String) throws {
        fatalError("init(itemProviderData:typeIdentifier:) is not supported")
    }
    #endif

    // MARK: - NSTextStorage primitives

    public override var string: String { backing.string }

    public override func attributes(at location: Int,
                                    effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    public override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters,
               range: range,
               changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    public override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Restyling

    public override func processEditing() {
        // Two rules we have to honor inside processEditing:
        //   1. Never call self.setAttributes / self.addAttributes here —
        //      they wrap in beginEditing/endEditing, which Apple's docs
        //      forbid during a process cycle. We mutate `backing` directly.
        //   2. Never call edited(.editedAttributes, range:) from in here
        //      with a wider range than what the user touched. The system
        //      MERGES it with the user's character edit into a single
        //      notification, and NSTextView's selection-adjustment then
        //      pushes the insertion point to the end of that widened range
        //      (which manifested as the cursor jumping per keystroke).
        //      Instead, ask the layout manager to re-render without going
        //      through the edit-notification path.
        let ns = backing.string as NSString
        guard ns.length > 0 else {
            super.processEditing()
            return
        }
        let touched = ns.lineRange(for: editedRange)
        restyleBacking(in: touched)
        super.processEditing()
        // Defer invalidation to the next runloop. Calling invalidateDisplay
        // / invalidateGlyphs from inside processEditing triggers glyph
        // generation while the textStorage is still considered editing
        // (endEditing is what called us), which iOS's NSLayoutManager
        // asserts against: "attempted glyph generation while textStorage is
        // editing." Mac's NSTextView tolerates it; UITextView in iOS 26
        // does not. Deferring by one runloop is invisible at typing speed
        // (the user's edited character renders via the system's own
        // edit-notification path; only the surrounding line's styling
        // catches up a frame later).
        let managers = layoutManagers
        DispatchQueue.main.async {
            for manager in managers {
                var actual = NSRange(location: NSNotFound, length: 0)
                manager.invalidateGlyphs(forCharacterRange: touched,
                                         changeInLength: 0,
                                         actualCharacterRange: &actual)
                manager.invalidateLayout(forCharacterRange: touched, actualCharacterRange: &actual)
                manager.invalidateDisplay(forCharacterRange: touched)
            }
        }
    }

    /// Restyles when something other than the text changed — base font, base
    /// color. Safe to wrap in its own edit cycle because we're outside any
    /// in-flight processEditing.
    private func restyleAll() {
        let full = NSRange(location: 0, length: backing.length)
        guard full.length > 0 else { return }
        beginEditing()
        restyleBacking(in: full)
        edited(.editedAttributes, range: full, changeInLength: 0)
        endEditing()
    }

    /// Push a new "where the cursor is now" range into the storage and
    /// re-apply marker fading for the whole document. Mutates `backing`
    /// directly (no edited() call) — selection-driven, not text-driven,
    /// so there's no edit cycle and the cursor doesn't move.
    public func setActiveLineRange(_ active: NSRange?) {
        if activeLineRange == active { return }
        activeLineRange = active
        let full = NSRange(location: 0, length: backing.length)
        guard full.length > 0 else { return }
        applyHideableMarkerFade(in: full)
        // Deferred display invalidation — same pattern as processEditing,
        // for the same reason (calling invalidate methods inside an edit
        // cycle on iOS asserts; selection updates are outside an edit
        // cycle but we keep the pattern for consistency).
        let managers = layoutManagers
        DispatchQueue.main.async {
            for manager in managers {
                manager.invalidateDisplay(forCharacterRange: full)
            }
        }
    }

    /// Walk hideable-marker ranges in `range` and set their foreground to
    /// either the normal marker color (if intersecting the active line) or
    /// the faded color (if not). Idempotent.
    private func applyHideableMarkerFade(in range: NSRange) {
        let faded = markerColor.withAlphaComponent(0.10)
        let active = activeLineRange
        backing.enumerateAttribute(.markdownHideableMarker, in: range, options: []) { value, run, _ in
            guard value != nil else { return }
            let color: PlatformColor
            if let active, NSIntersectionRange(run, active).length > 0 {
                color = self.markerColor
            } else if active == nil {
                // No active selection yet — leave at normal marker color.
                color = self.markerColor
            } else {
                color = faded
            }
            backing.addAttribute(.foregroundColor, value: color, range: run)
        }
    }

    /// Re-styles `backing` directly (no edited() calls). Whoever invokes this
    /// is responsible for posting a single edited() afterward.
    private func restyleBacking(in range: NSRange) {
        backing.removeAttribute(.strikethroughStyle, range: range)
        backing.removeAttribute(.strikethroughColor, range: range)
        backing.removeAttribute(.underlineStyle, range: range)
        backing.removeAttribute(.link, range: range)
        backing.removeAttribute(.markdownCheckboxState, range: range)
        backing.removeAttribute(.markdownHideableMarker, range: range)
        backing.removeAttribute(.paragraphStyle, range: range)
        backing.setAttributes([
            .font: baseFont,
            .foregroundColor: textColor,
        ], range: range)

        let runs = MarkdownSyntax.parse(backing.string)
        for run in runs where run.style != MarkdownStyle() {
            backing.addAttributes(attributes(for: run.style), range: run.range)
            // Tag inline markers as hideable so the active-line fade pass
            // can dim them when the cursor isn't on the same paragraph.
            // List prefixes (`- `, `* `) intentionally aren't tagged —
            // they're the visible bullet character itself.
            if run.style.isMarker, run.style.listMarker == nil {
                backing.addAttribute(.markdownHideableMarker, value: true, range: run.range)
            }
        }
        markCheckboxSlots(in: range)
        applyHideableMarkerFade(in: range)
    }

    /// Walk lines in `range`; for each line that starts with `- [ ] ` or
    /// `- [x] ` (or `*` variants), tag the 3-character `[ ]` / `[x]` slot
    /// with the `.markdownCheckboxState` attribute (Bool). The layout
    /// manager reads this attribute to swap the literal characters for a
    /// `☐` / `☑` glyph at draw time.
    private func markCheckboxSlots(in range: NSRange) {
        let ns = backing.string as NSString
        var cursor = range.location
        let end = range.upperBound
        while cursor < end {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            if let slot = detectCheckboxSlot(in: ns, lineStart: lineRange.location, lineLen: lineRange.length) {
                backing.addAttribute(.markdownCheckboxState, value: slot.checked, range: slot.range)
            }
            cursor = lineRange.upperBound
            if cursor <= lineRange.location { break }
        }
    }

    private func detectCheckboxSlot(in ns: NSString, lineStart: Int, lineLen: Int) -> (range: NSRange, checked: Bool)? {
        guard lineLen >= 6 else { return nil }
        let first = ns.character(at: lineStart)
        guard first == 0x2D || first == 0x2A else { return nil }
        guard ns.character(at: lineStart + 1) == 0x20 else { return nil }
        guard ns.character(at: lineStart + 2) == 0x5B else { return nil }
        let state = ns.character(at: lineStart + 3)
        guard state == 0x20 || state == 0x78 || state == 0x58 else { return nil }
        guard ns.character(at: lineStart + 4) == 0x5D else { return nil }
        guard ns.character(at: lineStart + 5) == 0x20 else { return nil }
        return (NSRange(location: lineStart + 2, length: 3), state == 0x78 || state == 0x58)
    }

    /// For lines that begin with a list marker, give the paragraph a hanging
    /// indent so wrapped content aligns with the start of the content after
    /// the marker (visually reads as a real bulleted list, not "-" prose).
    private func applyListParagraphStyles(in range: NSRange) {
        let ns = backing.string as NSString
        var cursor = range.location
        let end = range.upperBound
        while cursor < end {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let line = ns.substring(with: lineRange) as NSString
            if let indent = listIndent(for: line) {
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = 0
                style.headIndent = indent
                #if canImport(AppKit)
                style.paragraphSpacing = 1
                #endif
                backing.addAttribute(.paragraphStyle, value: style, range: lineRange)
            }
            cursor = lineRange.upperBound
            if cursor <= lineRange.location { break }  // safety
        }
    }

    /// Returns the head-indent (in points) for a list line, or nil if the
    /// line isn't a list item. The indent is the width of the marker prefix
    /// in `baseFont`, so wrapped content tucks under the first character of
    /// the item's text.
    private func listIndent(for line: NSString) -> CGFloat? {
        // mirrors MarkdownSyntax.detectList — keep in sync.
        guard line.length >= 2 else { return nil }
        let first = line.character(at: 0)
        guard first == 0x2D || first == 0x2A else { return nil }
        guard line.character(at: 1) == 0x20 else { return nil }
        var prefixLen = 2
        if line.length >= 6,
           line.character(at: 2) == 0x5B,
           (line.character(at: 3) == 0x20 || line.character(at: 3) == 0x78 || line.character(at: 3) == 0x58),
           line.character(at: 4) == 0x5D,
           line.character(at: 5) == 0x20 {
            prefixLen = 6
        }
        let prefix = line.substring(with: NSRange(location: 0, length: prefixLen)) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: baseFont]
        return prefix.size(withAttributes: attrs).width
    }

    // MARK: - Style → attribute mapping

    private func attributes(for style: MarkdownStyle) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        // Heading scales up + bolds. Levels 1/2/3.
        var scale: CGFloat = 1.0
        if let level = style.heading {
            switch level {
            case 1: scale = 1.35
            case 2: scale = 1.18
            default: scale = 1.08
            }
        }
        let bold = style.bold || style.heading != nil
        attrs[.font] = MarkdownTextStorage.styledFont(from: baseFont, bold: bold, italic: style.italic, scale: scale)

        if style.strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = markerColor
        }

        if let urlString = style.linkURL, let url = URL(string: urlString) {
            attrs[.link] = url
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[.foregroundColor] = textColor
        } else if style.isMarker {
            // Checkbox markers render more prominently than other markers —
            // the box is an interactive affordance (click-to-toggle), so it
            // should read as a UI element, not "syntax background noise."
            if let list = style.listMarker, list != .bullet {
                attrs[.foregroundColor] = textColor.markerVariant(alpha: 0.65)
            } else {
                attrs[.foregroundColor] = markerColor
            }
        } else {
            attrs[.foregroundColor] = textColor
        }
        return attrs
    }

    // MARK: - Font derivation

    static func styledFont(from base: PlatformFont,
                           bold: Bool,
                           italic: Bool,
                           scale: CGFloat) -> PlatformFont {
        let size = base.pointSize * scale
        #if canImport(AppKit)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let desc = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: desc, size: size) ?? base
        #else
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let desc = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: desc, size: size)
        }
        // Family doesn't carry the requested traits — fall back to size scale.
        return base.withSize(size)
        #endif
    }
}

// MARK: - Marker-color helper

public extension PlatformColor {
    /// Returns a muted version of this color suitable for syntax-marker
    /// rendering against a sticky background. Roughly 38% opacity of the
    /// original; tweak via `alpha`.
    func markerVariant(alpha: CGFloat = 0.38) -> PlatformColor {
        return self.withAlphaComponent(alpha)
    }
}
