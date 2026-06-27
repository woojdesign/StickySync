import AppKit
import NotesKit

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        var str = hex
        if str.hasPrefix("#") { str.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: str).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000FF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    /// Resolves to a different color in light vs dark appearance — the payoff
    /// of storing a color *token* rather than a frozen value.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        }
    }
}

/// Turns the platform-agnostic palette/font catalogs from NotesKit into
/// concrete AppKit colors and fonts.
enum Appearance {
    @MainActor
    static func background(for token: String) -> NSColor {
        let p = Palette.color(for: token)
        return .dynamic(
            light: .fromHex(p.lightBackgroundHex),
            dark:  .fromHex(p.darkBackgroundHex)
        )
    }

    @MainActor
    static func text(for token: String) -> NSColor {
        let p = Palette.color(for: token)
        return .dynamic(
            light: .fromHex(p.lightTextHex),
            dark:  .fromHex(p.darkTextHex)
        )
    }

    static func font(for option: FontOption, size: CGFloat) -> NSFont {
        switch option.kind {
        case .system:
            return NSFont.systemFont(ofSize: size)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size)
            if let d = base.fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: d, size: size) ?? base
            }
            return base
        case .serif:
            let base = NSFont.systemFont(ofSize: size)
            if let d = base.fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: d, size: size) ?? base
            }
            return base
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .named(let name):
            return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        }
    }

    /// A small horizontal strip of the theme's 7 slot colors, suitable as
    /// the leading icon of an NSMenuItem in the Theme submenu. The strip
    /// turns a 15-item list of names into something you can scan at a
    /// glance: visual recognition over textual memory.
    @MainActor
    static func themeSwatchImage(for theme: Theme) -> NSImage {
        let size = NSSize(width: 84, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        let cellW = size.width / CGFloat(theme.colors.count)
        for (i, color) in theme.colors.enumerated() {
            NSColor.fromHex(color.lightBackgroundHex).setFill()
            let rect = NSRect(
                x: CGFloat(i) * cellW, y: 0,
                width: cellW, height: size.height)
            rect.fill()
        }
        // A subtle hairline so the strip reads as one unit against varying
        // menu backgrounds (light/dark/Liquid Glass).
        NSColor.black.withAlphaComponent(0.12).setStroke()
        let border = NSBezierPath(rect: NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 0.5
        border.stroke()
        // Don't tint to template — the swatch IS the content.
        image.isTemplate = false
        return image
    }
}
