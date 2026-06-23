import SwiftUI
import UIKit
import NotesKit
import WoojTokens

// wooj-tokens test: map NotesKit's note tokens onto the WoojSticky range and use
// wooj ink for text. WoojColor/WoojSticky are already SwiftUI Colors, so there's
// no bridge here (unlike the macOS AppKit side).
enum Appearance {
    private static let woojSticky: [String: Color] = [
        "butter": WoojSticky.butter, "peach": WoojSticky.apricot, "rose": WoojSticky.rose,
        "lilac": WoojSticky.lilac, "sky": WoojSticky.sky, "mint": WoojSticky.sage, "sand": WoojSticky.cream
    ]

    static func background(_ token: String) -> Color { woojSticky[token] ?? WoojSticky.butter }

    static func text(_ token: String) -> Color { WoojColor.ink }

    static func font(_ id: String, size: CGFloat) -> Font {
        switch FontCatalog.option(for: id).kind {
        case .system:          return .system(size: size)
        case .rounded:         return .system(size: size, design: .rounded)
        case .serif:           return .custom(WoojType.reading.family, size: size)  // Charter (wooj reading)
        case .monospaced:      return .system(size: size, design: .monospaced)
        case .named(let name): return .custom(name, size: size)
        }
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
