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
    /// Applies the platform-convention scale so `note.fontSize` matches its
    /// perceived weight across Mac and iPhone — see `iosReadingSize(_:)`.
    static func uiFont(_ id: String, size: CGFloat) -> UIFont {
        let scaled = iosReadingSize(size)
        switch FontCatalog.option(for: id).kind {
        case .system:
            return .systemFont(ofSize: scaled)
        case .rounded:
            let base = UIFont.systemFont(ofSize: scaled)
            if let d = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: d, size: scaled)
            }
            return base
        case .serif:
            return UIFont(name: WoojType.reading.family, size: scaled) ?? .systemFont(ofSize: scaled)
        case .monospaced:
            return .monospacedSystemFont(ofSize: scaled, weight: .regular)
        case .named(let name):
            return UIFont(name: name, size: scaled) ?? .systemFont(ofSize: scaled)
        }
    }

    /// Convert a `note.fontSize` (the cross-platform "logical" size the
    /// note carries on disk and in CloudKit) into the size we actually
    /// render at on iPhone. Mac uses the logical size 1:1; iOS multiplies
    /// because the platforms have different reading-distance conventions:
    ///
    /// - macOS body text convention: ~13pt at typical screen distance
    ///   (50cm), so a 15pt note reads comfortably "above body."
    /// - iOS body text convention: ~17pt at typical hold distance
    ///   (~30cm), so the SAME 15pt note read on iPhone feels too small.
    ///
    /// A 1.2x scale lifts the default 15pt to 18pt — squarely in iOS
    /// body territory — and preserves the user's relative bigger/smaller
    /// adjustments (12 → 14.4, 18 → 21.6, 24 → 28.8). Applied at the
    /// render boundary, not stored on the note, so the synced size stays
    /// platform-agnostic.
    static func iosReadingSize(_ logical: CGFloat) -> CGFloat {
        logical * iosReadingScale
    }

    static let iosReadingScale: CGFloat = 1.2

    /// A small horizontal strip of the theme's 7 slot colors, suitable as
    /// the leading icon of a `Label(title:icon:)` in the SwiftUI theme
    /// Menu. Mirrors the macOS version in `StickySync/Appearance.swift`.
    /// Renders via `UIGraphicsImageRenderer` at the screen scale so the
    /// colors stay crisp on Retina; `.alwaysOriginal` so SwiftUI doesn't
    /// re-tint the strip.
    @MainActor
    static func themeSwatchImage(for theme: Theme) -> UIImage {
        let size = CGSize(width: 84, height: 14)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cellW = size.width / CGFloat(theme.colors.count)
            for (i, color) in theme.colors.enumerated() {
                UIColor.fromHex(color.lightBackgroundHex).setFill()
                let rect = CGRect(x: CGFloat(i) * cellW, y: 0,
                                  width: cellW, height: size.height)
                ctx.cgContext.fill(rect)
            }
            UIColor.black.withAlphaComponent(0.12).setStroke()
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 0.25, dy: 0.25))
        }.withRenderingMode(.alwaysOriginal)
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
