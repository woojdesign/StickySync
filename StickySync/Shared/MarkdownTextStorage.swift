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
        // Inside processEditing we MUST NOT call self.setAttributes /
        // self.addAttributes — those wrap in beginEditing/endEditing, which
        // Apple's docs forbid here (and which manifested as the cursor
        // snapping to end-of-text after every keystroke). Instead, mutate
        // the backing store directly and post a single edited() notification.
        let full = NSRange(location: 0, length: backing.length)
        if full.length > 0 {
            restyleBacking(in: full)
            edited(.editedAttributes, range: full, changeInLength: 0)
        }
        super.processEditing()
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

    /// Re-styles `backing` directly (no edited() calls). Whoever invokes this
    /// is responsible for posting a single edited() afterward.
    private func restyleBacking(in range: NSRange) {
        backing.removeAttribute(.strikethroughStyle, range: range)
        backing.removeAttribute(.strikethroughColor, range: range)
        backing.removeAttribute(.underlineStyle, range: range)
        backing.removeAttribute(.link, range: range)
        backing.removeAttribute(.paragraphStyle, range: range)
        backing.setAttributes([
            .font: baseFont,
            .foregroundColor: textColor,
        ], range: range)

        let runs = MarkdownSyntax.parse(backing.string)
        for run in runs where run.style != MarkdownStyle() {
            backing.addAttributes(attributes(for: run.style), range: run.range)
        }
        applyListParagraphStyles(in: range)
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
            attrs[.foregroundColor] = markerColor
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
