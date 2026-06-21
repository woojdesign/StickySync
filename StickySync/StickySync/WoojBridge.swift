#if os(macOS)
import AppKit
import SwiftUI

// Bridges the SwiftUI-based wooj-tokens to the AppKit NSColor/NSFont that
// StickySync draws with. No hex is re-typed here — every value comes from
// WoojTokens. (Guarded to macOS so it can't reach an iOS target.)
extension NSColor {
    static let woojGround    = NSColor(WoojColor.ground)
    static let woojSurface   = NSColor(WoojColor.surface)
    static let woojPaper     = NSColor(WoojColor.paper)
    static let woojInk        = NSColor(WoojColor.ink)
    static let woojSecondary = NSColor(WoojColor.secondary)
    static let woojTertiary  = NSColor(WoojColor.tertiary)
    static let woojLine      = NSColor(WoojColor.line)
    static let woojClay      = NSColor(WoojColor.clay)
    static let woojOnClay    = NSColor(WoojColor.onClay)

    /// Note range, palette order.
    static let woojStickies: [NSColor] = WoojSticky.all.map(NSColor.init)

    // Named stickies, for mapping StickySync's tokens → the wooj note range.
    static let woojButter  = NSColor(WoojSticky.butter)
    static let woojApricot = NSColor(WoojSticky.apricot)
    static let woojRose    = NSColor(WoojSticky.rose)
    static let woojBlush   = NSColor(WoojSticky.blush)
    static let woojLilac   = NSColor(WoojSticky.lilac)
    static let woojSage    = NSColor(WoojSticky.sage)
    static let woojSky     = NSColor(WoojSticky.sky)
    static let woojCream   = NSColor(WoojSticky.cream)
}

extension NSFont {
    /// System fallback until the custom faces are bundled (expected).
    static func wooj(_ s: WoojTextStyle) -> NSFont {
        NSFont(name: s.family, size: s.size) ?? .systemFont(ofSize: s.size)
    }
}
#endif
