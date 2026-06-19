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
    static func background(for token: String) -> NSColor {
        let c = Palette.color(for: token)
        return .dynamic(light: .fromHex(c.lightBackgroundHex), dark: .fromHex(c.darkBackgroundHex))
    }

    static func text(for token: String) -> NSColor {
        let c = Palette.color(for: token)
        return .dynamic(light: .fromHex(c.lightTextHex), dark: .fromHex(c.darkTextHex))
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
}
