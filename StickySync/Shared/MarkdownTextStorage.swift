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
public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformImage = UIImage
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

    /// Resolves an attachment UUID to its rendered image. Set by the host
    /// view (`MarkdownTextView` / `NoteContentView`) to bridge into the
    /// NotesKit store. The substitution pass uses this to hydrate inline
    /// `NSTextAttachment` images at parse time.
    public var attachmentLoader: ((UUID) -> PlatformImage?)?

    /// Max pixel width an inline image may render at. Smaller images
    /// keep their natural size; anything wider gets scaled to fit.
    public var attachmentMaxWidth: CGFloat = 320

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

    // MARK: - Source-faithful round-trip
    //
    // Inline images live as `\u{FFFC}` (NSAttachmentCharacter) in `backing`,
    // tagged with `.markdownAttachmentSource` carrying the original
    // `![alt](attachment://UUID)` text. The editor's binding always sees the
    // *expanded* Markdown form, so what NotesKit persists stays portable.

    /// Expanded Markdown — replaces every attachment FFFC with its stored
    /// `.markdownAttachmentSource` text. Use this (not `string`) when handing
    /// content back to the binding or to NotesKit.
    public var sourceString: String {
        var out = ""
        let full = NSRange(location: 0, length: backing.length)
        let raw = backing.string as NSString
        var cursor = 0
        backing.enumerateAttribute(.markdownAttachmentSource, in: full, options: []) { value, range, _ in
            if range.location > cursor {
                out += raw.substring(with: NSRange(location: cursor, length: range.location - cursor))
            }
            if let source = value as? String {
                out += source
            } else {
                out += raw.substring(with: range)
            }
            cursor = range.upperBound
        }
        if cursor < raw.length {
            out += raw.substring(with: NSRange(location: cursor, length: raw.length - cursor))
        }
        return out
    }

    /// Walk `backing` for `![alt](attachment://UUID)` patterns and replace
    /// each with a single `\u{FFFC}` carrying the inline image attachment +
    /// the source-attribute round-trip metadata. Idempotent — re-scanning
    /// after a substitution is a no-op because the matched runs are gone.
    ///
    /// Call after any `replaceCharacters(in:with:)` that inserts new
    /// Markdown source (the initial load + any external content sync).
    public func substituteAttachmentReferences() {
        let pattern = try! NSRegularExpression(
            pattern: #"!\[([^\]]*)\]\(attachment://([0-9a-fA-F\-]+)\)"#,
            options: []
        )
        let full = NSRange(location: 0, length: backing.length)
        let matches = pattern.matches(in: backing.string, options: [], range: full)
        // Walk back-to-front so prior offsets stay valid as we replace.
        for match in matches.reversed() {
            guard match.numberOfRanges == 3 else { continue }
            let altRange = match.range(at: 1)
            let uuidRange = match.range(at: 2)
            let source = (backing.string as NSString).substring(with: match.range)
            let altText = (backing.string as NSString).substring(with: altRange)
            let uuidString = (backing.string as NSString).substring(with: uuidRange)
            guard let uuid = UUID(uuidString: uuidString) else { continue }
            substituteAttachment(at: match.range,
                                 source: source,
                                 altText: altText,
                                 attachmentID: uuid)
        }
    }

    /// Insert a fresh attachment placeholder at `location` — used by the
    /// paste handler after it has uploaded the image bytes to NotesKit.
    /// The caller has the UUID and the image already; we just need to
    /// stitch in the FFFC + attributes.
    public func insertAttachment(id: UUID,
                                 altText: String,
                                 image: PlatformImage,
                                 at location: Int) {
        let source = "![\(altText)](attachment://\(id.uuidString))"
        let placeholder = "\u{FFFC}"
        beginEditing()
        backing.replaceCharacters(in: NSRange(location: location, length: 0), with: placeholder)
        let placeholderRange = NSRange(location: location, length: 1)
        applyAttachmentAttributes(in: placeholderRange,
                                  source: source,
                                  attachmentID: id,
                                  image: image)
        edited(.editedCharacters, range: NSRange(location: location, length: 0),
               changeInLength: 1)
        edited(.editedAttributes, range: placeholderRange, changeInLength: 0)
        endEditing()
    }

    /// Replace a `![alt](attachment://UUID)` source span with the
    /// FFFC placeholder and re-add the typing attributes. Called by
    /// `substituteAttachmentReferences()` after parsing.
    private func substituteAttachment(at range: NSRange,
                                      source: String,
                                      altText: String,
                                      attachmentID: UUID) {
        let placeholder = "\u{FFFC}"
        beginEditing()
        backing.replaceCharacters(in: range, with: placeholder)
        let placeholderRange = NSRange(location: range.location, length: 1)
        let image = attachmentLoader?(attachmentID)
        applyAttachmentAttributes(in: placeholderRange,
                                  source: source,
                                  attachmentID: attachmentID,
                                  image: image)
        // Re-emit edits so the layout manager re-flows. The character delta
        // is negative (FFFC is one char; source was many).
        edited(.editedCharacters, range: range, changeInLength: 1 - range.length)
        edited(.editedAttributes, range: placeholderRange, changeInLength: 0)
        endEditing()
    }

    /// Set the NSTextAttachment + round-trip metadata for an FFFC at
    /// `range` (must be length 1). When `image` is nil — the attachment
    /// hasn't downloaded yet — we draw a sized placeholder so the layout
    /// reserves the space.
    private func applyAttachmentAttributes(in range: NSRange,
                                           source: String,
                                           attachmentID: UUID,
                                           image: PlatformImage?) {
        let attachment = NSTextAttachment()
        if let image {
            attachment.image = image
            let scaled = scaledBounds(for: image, maxWidth: attachmentMaxWidth)
            attachment.bounds = scaled
        } else {
            // Placeholder until the loader returns. 200x140 reads as "image
            // here" without being a tiny dot.
            attachment.bounds = CGRect(x: 0, y: 0, width: 200, height: 140)
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
            .attachment: attachment,
            .markdownAttachmentSource: source,
            .markdownAttachmentID: attachmentID
        ]
        // Attachments interact poorly with paragraph styles meant for body
        // text (e.g. `paragraphSpacingBefore`). Default paragraph keeps them
        // breathing without inheriting list indents from the surrounding text.
        attrs[.paragraphStyle] = NSParagraphStyle.default
        backing.setAttributes(attrs, range: range)
    }

    private func scaledBounds(for image: PlatformImage,
                              maxWidth: CGFloat) -> CGRect {
        #if canImport(AppKit)
        let imgSize = image.size
        #else
        let imgSize = image.size
        #endif
        let scale = min(1.0, maxWidth / max(imgSize.width, 1))
        let w = imgSize.width * scale
        let h = imgSize.height * scale
        return CGRect(x: 0, y: 0, width: w, height: h)
    }

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

    /// Walk hideable-marker ranges in `range`. For each one:
    ///   • inside the active paragraph → normal marker color, base font
    ///     (fully visible, normal width).
    ///   • outside the active paragraph → clear color + ~0pt font (truly
    ///     hidden, ~0 width — the layout reflows so the word reads as if
    ///     the marker isn't there).
    /// `activeLineRange == nil` (no selection seen yet) keeps all markers
    /// at their normal style so the user isn't surprised by hidden syntax
    /// on the very first render.
    private func applyHideableMarkerFade(in range: NSRange) {
        let active = activeLineRange
        let hiddenFont = Self.hiddenFont
        let clear = PlatformColor.clear
        backing.enumerateAttribute(.markdownHideableMarker, in: range, options: []) { value, run, _ in
            guard value != nil else { return }
            let visible: Bool
            if let active {
                visible = NSIntersectionRange(run, active).length > 0
            } else {
                visible = true
            }
            if visible {
                backing.addAttribute(.foregroundColor, value: self.markerColor, range: run)
                backing.addAttribute(.font, value: self.baseFont, range: run)
            } else {
                backing.addAttribute(.foregroundColor, value: clear, range: run)
                backing.addAttribute(.font, value: hiddenFont, range: run)
            }
        }
    }

    /// A near-zero-point font shared across all hidden markers. 0.01pt
    /// gives an advance width of effectively zero — the markers occupy no
    /// visible space when hidden. (0pt is invalid; 0.01 is the canonical
    /// "as close to invisible as possible" value.)
    private static let hiddenFont: PlatformFont = {
        #if canImport(AppKit)
        return NSFont.systemFont(ofSize: 0.01)
        #else
        return UIFont.systemFont(ofSize: 0.01)
        #endif
    }()

    /// Re-styles `backing` directly (no edited() calls). Whoever invokes this
    /// is responsible for posting a single edited() afterward.
    private func restyleBacking(in range: NSRange) {
        // Walk the touched range and skip any FFFC attachment placeholder
        // spans — the restyle pass below would otherwise stomp the
        // `.attachment`, `.markdownAttachmentSource`, and
        // `.markdownAttachmentID` attributes set by `insertAttachment` /
        // `substituteAttachmentReferences`, and the inline image would
        // silently disappear after the next edit cycle.
        let nonAttachmentRanges = nonAttachmentSubranges(of: range)

        for sub in nonAttachmentRanges {
            backing.removeAttribute(.strikethroughStyle, range: sub)
            backing.removeAttribute(.strikethroughColor, range: sub)
            backing.removeAttribute(.underlineStyle, range: sub)
            backing.removeAttribute(.link, range: sub)
            backing.removeAttribute(.markdownCheckboxState, range: sub)
            backing.removeAttribute(.markdownHideableMarker, range: sub)
            backing.removeAttribute(.paragraphStyle, range: sub)
            backing.setAttributes([
                .font: baseFont,
                .foregroundColor: textColor,
            ], range: sub)
        }

        let runs = MarkdownSyntax.parse(backing.string)
        for run in runs where run.style != MarkdownStyle() {
            // Clip each parsed run to the non-attachment portions so we
            // don't restyle through an inline image.
            for sub in nonAttachmentRanges {
                guard let clipped = sub.intersection(run.range) else { continue }
                backing.addAttributes(attributes(for: run.style), range: clipped)
                if run.style.isMarker, run.style.listMarker == nil {
                    backing.addAttribute(.markdownHideableMarker, value: true, range: clipped)
                }
            }
        }
        markCheckboxSlots(in: range)
        applyHideableMarkerFade(in: range)
    }

    /// Returns the sub-ranges of `range` that don't intersect any
    /// `.markdownAttachmentID` span. Used by `restyleBacking` to avoid
    /// stomping the inline-image attachment attributes during a restyle.
    private func nonAttachmentSubranges(of range: NSRange) -> [NSRange] {
        var attachmentRanges: [NSRange] = []
        backing.enumerateAttribute(.markdownAttachmentID, in: range, options: []) { value, attachmentRange, _ in
            if value != nil { attachmentRanges.append(attachmentRange) }
        }
        if attachmentRanges.isEmpty { return [range] }

        var out: [NSRange] = []
        var cursor = range.location
        for ar in attachmentRanges {
            if ar.location > cursor {
                out.append(NSRange(location: cursor, length: ar.location - cursor))
            }
            cursor = ar.upperBound
        }
        if cursor < range.upperBound {
            out.append(NSRange(location: cursor, length: range.upperBound - cursor))
        }
        return out
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
