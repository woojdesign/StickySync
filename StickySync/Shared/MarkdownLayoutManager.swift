// MarkdownLayoutManager.swift
//
// NSLayoutManager subclass that intercepts glyph drawing for Markdown syntax
// that should be rendered as something other than its literal source text:
//
//   • Checkbox slots: `[ ]` / `[x]` characters are skipped from default
//     rendering and replaced with `☐` / `☑` glyphs drawn at the same
//     character-width as the source (so the underlying string length is
//     unchanged — preserves cursor, selection, IME, undo, copy/paste).
//
// Follows the pattern Apple's Developer Technical Support recommends for
// TextKit-based editors that want display-time substitution: keep the source
// stable, swap glyphs at draw time. (Same-length substitution avoids the
// known coordinate-mapping bugs with NSTextContentStorage's textParagraphWith
// delegate path.)
//
// The text storage marks slot ranges by setting the
// `.markdownCheckboxState` attribute (Bool: true = checked). This file owns
// only the rendering — the marker attribute is set by MarkdownTextStorage.

import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public extension NSAttributedString.Key {
    /// Marks a 3-character `[ ]` (or `[x]`) slot for substituted glyph
    /// rendering. Value is a `Bool`: `true` = checked.
    static let markdownCheckboxState = NSAttributedString.Key("markdownCheckboxState")
    /// Marks an inline-syntax marker that should fade when the cursor isn't
    /// on the same paragraph. `**`, `_`, `~~`, `#`, and link brackets get
    /// this tag at parse time. List markers (`- `, `* `) are NOT tagged —
    /// they're the visual bullet itself, never hidden.
    static let markdownHideableMarker = NSAttributedString.Key("markdownHideableMarker")
}

public final class MarkdownLayoutManager: NSLayoutManager {

    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        // Collect substitution slots in this draw region. Empty fast path
        // handles the overwhelmingly common case (no checkboxes on screen).
        var slots: [(range: NSRange, checked: Bool)] = []
        storage.enumerateAttribute(.markdownCheckboxState, in: charRange, options: []) { value, range, _ in
            if let checked = value as? Bool {
                slots.append((range, checked))
            }
        }
        if slots.isEmpty {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        // Walk the draw range in order: default-draw everything OUTSIDE the
        // slots, custom-draw the slots themselves.
        let sorted = slots.sorted { $0.range.location < $1.range.location }
        var nextChar = charRange.location
        for slot in sorted {
            if slot.range.location > nextChar {
                let beforeChars = NSRange(location: nextChar, length: slot.range.location - nextChar)
                let beforeGlyphs = glyphRange(forCharacterRange: beforeChars, actualCharacterRange: nil)
                super.drawGlyphs(forGlyphRange: beforeGlyphs, at: origin)
            }
            drawCheckboxGlyph(in: slot.range, origin: origin, isChecked: slot.checked, storage: storage)
            nextChar = slot.range.upperBound
        }
        if nextChar < charRange.upperBound {
            let afterChars = NSRange(location: nextChar, length: charRange.upperBound - nextChar)
            let afterGlyphs = glyphRange(forCharacterRange: afterChars, actualCharacterRange: nil)
            super.drawGlyphs(forGlyphRange: afterGlyphs, at: origin)
        }
    }

    private func drawCheckboxGlyph(in characterRange: NSRange,
                                   origin: CGPoint,
                                   isChecked: Bool,
                                   storage: NSTextStorage) {
        let slotGlyphs = glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard let container = textContainer(forGlyphAt: slotGlyphs.location, effectiveRange: nil) else { return }
        let rect = boundingRect(forGlyphRange: slotGlyphs, in: container)

        // Pull font + color from the slot's source attributes so the glyph
        // matches the surrounding text size + the host's chosen marker color.
        let attrs = storage.attributes(at: characterRange.location, effectiveRange: nil)
        let font = (attrs[.font] as? PlatformFont) ?? defaultFont()
        let color = (attrs[.foregroundColor] as? PlatformColor) ?? defaultColor()

        let glyph = isChecked ? "☑" : "☐" as NSString
        let drawAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]

        // Position the glyph at the left edge of the slot's bounding rect.
        // The remaining 2-character width of the slot becomes visual breathing
        // room between the box and the item text — which reads naturally for
        // a checklist.
        let drawPoint = CGPoint(x: origin.x + rect.minX, y: origin.y + rect.minY)
        glyph.draw(at: drawPoint, withAttributes: drawAttrs)
    }

    private func defaultFont() -> PlatformFont {
        #if canImport(AppKit)
        return NSFont.systemFont(ofSize: 14)
        #else
        return UIFont.systemFont(ofSize: 14)
        #endif
    }

    private func defaultColor() -> PlatformColor {
        #if canImport(AppKit)
        return NSColor.labelColor
        #else
        return UIColor.label
        #endif
    }
}
