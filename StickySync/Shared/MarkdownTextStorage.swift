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
        // Re-parse + re-apply attributes for the whole string. Sticky notes
        // are short; full re-parse is faster than the bookkeeping to scope
        // changes to a paragraph range, and is correct under any edit shape.
        let full = NSRange(location: 0, length: backing.length)
        if full.length > 0 {
            applyBaselineAttributes(in: full)
            let runs = MarkdownSyntax.parse(backing.string)
            for run in runs where run.style != MarkdownStyle() {
                let merged = attributes(for: run.style)
                addAttributes(merged, range: run.range)
            }
        }
        super.processEditing()
    }

    /// Re-styles without an edit having happened — e.g. when the base font or
    /// colors change. Calls into the same code path via a no-op edited().
    private func restyleAll() {
        let full = NSRange(location: 0, length: backing.length)
        guard full.length > 0 else { return }
        beginEditing()
        applyBaselineAttributes(in: full)
        let runs = MarkdownSyntax.parse(backing.string)
        for run in runs where run.style != MarkdownStyle() {
            let merged = attributes(for: run.style)
            addAttributes(merged, range: run.range)
        }
        edited(.editedAttributes, range: full, changeInLength: 0)
        endEditing()
    }

    private func applyBaselineAttributes(in range: NSRange) {
        // Strip prior overrides first; otherwise stale strikethrough/links
        // bleed when characters are deleted.
        removeAttribute(.strikethroughStyle, range: range)
        removeAttribute(.strikethroughColor, range: range)
        removeAttribute(.underlineStyle, range: range)
        removeAttribute(.link, range: range)
        setAttributes([
            .font: baseFont,
            .foregroundColor: textColor,
        ], range: range)
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
