import SwiftUI
import NotesKit

// Turns NotesKit's platform-agnostic palette/font tokens into SwiftUI colors
// and fonts — the iOS counterpart of the macOS app's AppKit `Appearance`.

extension UIColor {
    convenience init(stickyHex hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v & 0xFF0000) >> 16) / 255,
                  green: CGFloat((v & 0x00FF00) >> 8) / 255,
                  blue: CGFloat(v & 0x0000FF) / 255,
                  alpha: 1)
    }
}

enum Appearance {
    /// Resolves to light/dark automatically — the payoff of storing a color
    /// *token* rather than a frozen value.
    static func background(_ token: String) -> Color {
        let c = Palette.color(for: token)
        return Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(stickyHex: c.darkBackgroundHex)
            : UIColor(stickyHex: c.lightBackgroundHex) })
    }

    static func text(_ token: String) -> Color {
        let c = Palette.color(for: token)
        return Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(stickyHex: c.darkTextHex)
            : UIColor(stickyHex: c.lightTextHex) })
    }

    static func font(_ id: String, size: CGFloat) -> Font {
        switch FontCatalog.option(for: id).kind {
        case .system:          return .system(size: size)
        case .rounded:         return .system(size: size, design: .rounded)
        case .serif:           return .system(size: size, design: .serif)
        case .monospaced:      return .system(size: size, design: .monospaced)
        case .named(let name): return .custom(name, size: size)
        }
    }
}
