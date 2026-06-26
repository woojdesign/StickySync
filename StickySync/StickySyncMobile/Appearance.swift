import SwiftUI
import UIKit
import NotesKit
import WoojTokens

enum Appearance {
    @MainActor
    static func background(_ token: String) -> Color {
        let p = Palette.color(for: token)
        return Color(uiColor: UIColor.dynamic(
            light: .fromHex(p.lightBackgroundHex),
            dark:  .fromHex(p.darkBackgroundHex)
        ))
    }

    @MainActor
    static func text(_ token: String) -> Color {
        let p = Palette.color(for: token)
        return Color(uiColor: UIColor.dynamic(
            light: .fromHex(p.lightTextHex),
            dark:  .fromHex(p.darkTextHex)
        ))
    }

    static func font(_ id: String, size: CGFloat) -> Font {
        switch FontCatalog.option(for: id).kind {
        case .system:          return .system(size: size)
        case .rounded:         return .system(size: size, design: .rounded)
        case .serif:           return .custom(WoojType.reading.family, size: size)  // Charter (wooj reading)
        case .monospaced:      return .system(size: size, design: .monospaced)
        case .named(let name): return .custom(name, size: size)
        }
    }

    /// UIKit equivalent of `background(_:)` for editors that need a UIColor
    /// directly (Markdown text view sets its own UIColor backgrounds).
    @MainActor
    static func uiBackground(_ token: String) -> UIColor {
        let p = Palette.color(for: token)
        return .dynamic(light: .fromHex(p.lightBackgroundHex),
                        dark:  .fromHex(p.darkBackgroundHex))
    }

    /// UIKit equivalent of `text(_:)`.
    @MainActor
    static func uiText(_ token: String) -> UIColor {
        let p = Palette.color(for: token)
        return .dynamic(light: .fromHex(p.lightTextHex),
                        dark:  .fromHex(p.darkTextHex))
    }

    /// UIFont equivalent for use with UIKit-backed editors (Markdown wrapper).
    static func uiFont(_ id: String, size: CGFloat) -> UIFont {
        switch FontCatalog.option(for: id).kind {
        case .system:
            return .systemFont(ofSize: size)
        case .rounded:
            let base = UIFont.systemFont(ofSize: size)
            if let d = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: d, size: size)
            }
            return base
        case .serif:
            return UIFont(name: WoojType.reading.family, size: size) ?? .systemFont(ofSize: size)
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .named(let name):
            return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
        }
    }
}

extension UIColor {
    static func fromHex(_ hex: String) -> UIColor {
        var str = hex
        if str.hasPrefix("#") { str.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: str).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((value & 0x00FF00) >> 8)  / 255.0
        let b = CGFloat( value & 0x0000FF)        / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// Resolves to a different color in light vs dark trait collections —
    /// the payoff of storing a color *token* rather than a frozen value.
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        }
    }
}
